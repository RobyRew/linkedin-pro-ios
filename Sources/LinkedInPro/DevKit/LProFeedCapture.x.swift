import Foundation
import ObjectiveC.runtime

// DevKit feed capture - a reverse-engineering instrument, NOT a shipping feature.
//
// Records, from the earliest possible point, the feed traffic between the app and
// the server: the REQUESTS LinkedIn sends (Voyager / GraphQL feed queries) and the
// RESPONSES it receives (the raw SDUI / feed JSON). It is meant for a clean run
// with every filter disabled, so the raw payloads can be pulled over USB and
// analysed to decide what to block at the data layer.
//
// Two capture points, both installed at launch (so the very first feed load is
// covered):
//   - RESPONSES: swizzle NSJSONSerialization (the boundary every JSON parse passes
//     through, LinkedIn's frameworks included) and write the raw bytes of feed /
//     voyager payloads to the capture file. The parsed object is returned unchanged.
//   - REQUESTS: discover the concrete URLSessionDataTask class at runtime and
//     swizzle -resume, logging each feed / voyager / graphql request's method, URL,
//     headers and body before it is sent. Read-only; the task is resumed normally.
//
// Gating + safety:
//   - Installs only when DevKit is enabled AND the capture flag is on; a normal
//     build never swizzles anything here.
//   - A cheap raw-bytes marker test gates the (hot) JSON path, so non-feed JSON is
//     skipped before any copy / write.
//   - File writes are serialized on a private queue; per-record and total-size caps
//     stop a runaway. The file lives in Documents, which the sideload build exposes
//     (UIFileSharingEnabled), so it can be pulled over USB.
enum LProFeedCapture {
    private static var installed = false
    // Cheap gate read on the hot path (avoids a UserDefaults / file-exists read per
    // JSON parse). Set true at install; the settings toggle flips it live.
    private static var runtimeEnabled = false
    private static let queue = DispatchQueue(label: "com.linkedinpro.feedcapture")

    // Raw-bytes markers that identify a feed / voyager payload or request.
    private static let responseNeedles: [Data] = [
        "feedDashMainFeed", "voyagerFeedDash", "com.linkedin.voyager.dash.feed",
        "feedComponent", "componentKey", "mainFeed", "updateV2",
    ].map { Data($0.utf8) }
    private static let urlNeedles = ["voyager", "graphql", "feed", "/api/"]

    // Caps: generous per-record (feed payloads are large and the point is full
    // data), with a total ceiling so a long session cannot fill the disk.
    private static let perResponseCap = 3_000_000
    private static let perRequestBodyCap = 262_144
    private static let totalCap = 160 * 1024 * 1024
    private static var totalWritten = 0
    private static var capped = false

    static var isActive: Bool { LProDevKit.isEnabled && UserDefaults.lproFeedCaptureEnabled }

    static func fileURL() -> URL? {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        return docs.appendingPathComponent("feed-capture.txt")
    }

    static func install() {
        guard isActive, !installed else { return }
        installed = true
        runtimeEnabled = true
        swizzleJSON()
        swizzleTaskResume()
        swizzleSessionFactory()      // delegate-based response bodies
        swizzleCompletionHandler()   // completion-based response bodies
        let stamp = ISO8601DateFormatter().string(from: Date())
        append(header: "SESSION START \(stamp)  (filters should be OFF for a clean capture)")
        LProLog.write("[capture] feed capture armed -> \(fileURL()?.path ?? "?")")
    }

    // Settings toggle. The capture points are swizzled once at launch, so turning
    // capture OFF stops writing immediately, but turning it ON only resumes writing
    // if it was armed at launch - otherwise a relaunch is needed to install the
    // swizzles. Reports which case applies.
    @discardableResult
    static func setEnabled(_ on: Bool) -> String {
        UserDefaults.lproFeedCaptureEnabled = on
        if on, !installed {
            LProLog.write("[capture] enabled, but not armed this launch - relaunch to start capturing")
            return "Capture will start after you relaunch LinkedIn."
        }
        runtimeEnabled = on
        LProLog.write("[capture] \(on ? "resumed" : "paused")")
        return on ? "Capturing feed traffic." : "Capture paused."
    }

    static func clear() {
        queue.async {
            if let url = fileURL() { try? FileManager.default.removeItem(at: url) }
            totalWritten = 0
            capped = false
        }
        LProLog.write("[capture] cleared")
    }

    static func sizeString() -> String {
        guard let url = fileURL(),
              let n = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int else { return "0 B" }
        if n > 1_048_576 { return String(format: "%.1f MB", Double(n) / 1_048_576) }
        if n > 1024 { return "\(n / 1024) KB" }
        return "\(n) B"
    }

    // MARK: - responses (NSJSONSerialization)

    private static func swizzleJSON() {
        let sel = NSSelectorFromString("JSONObjectWithData:options:error:")
        guard let method = class_getClassMethod(JSONSerialization.self, sel) else { return }
        typealias Fn = @convention(c) (AnyObject, Selector, NSData, UInt,
                                       UnsafeMutablePointer<NSError?>?) -> AnyObject?
        let orig = unsafeBitCast(method_getImplementation(method), to: Fn.self)
        let block: @convention(block) (AnyObject, NSData, UInt,
                                       UnsafeMutablePointer<NSError?>?) -> AnyObject? = { obj, data, opts, err in
            let result = orig(obj, sel, data, opts, err)
            LProFeedCapture.noteResponse(data)
            return result
        }
        method_setImplementation(method, imp_implementationWithBlock(block))
    }

    private static func noteResponse(_ nsdata: NSData) {
        guard runtimeEnabled, !capped, nsdata.length > 512 else { return }
        let data = nsdata as Data
        // Cheap gate on the calling thread: only feed-shaped payloads go further.
        guard responseNeedles.contains(where: { data.range(of: $0) != nil }) else { return }
        let slice = data.count > perResponseCap ? data.prefix(perResponseCap) : data
        let truncated = data.count > perResponseCap
        queue.async {
            guard !capped else { return }
            let body = String(data: slice, encoding: .utf8) ?? "(non-UTF8 \(data.count) bytes)"
            appendRecord("RESP \(stamp()) \(data.count)B\(truncated ? " (truncated)" : "")", body)
        }
    }

    // MARK: - requests (URLSessionDataTask.resume)

    private static func swizzleTaskResume() {
        // Discover the concrete data-task class from a throwaway task (never resumed).
        guard let url = URL(string: "https://127.0.0.1/__lpro_probe") else { return }
        let probe = URLSession.shared.dataTask(with: URLRequest(url: url))
        let taskClass: AnyClass = object_getClass(probe) ?? type(of: probe)
        probe.cancel()

        let sel = NSSelectorFromString("resume")
        guard let method = class_getInstanceMethod(taskClass, sel) else {
            LProLog.write("[capture] could not find -resume on \(taskClass)")
            return
        }
        typealias Fn = @convention(c) (AnyObject, Selector) -> Void
        let orig = unsafeBitCast(method_getImplementation(method), to: Fn.self)
        let block: @convention(block) (AnyObject) -> Void = { taskObj in
            if let task = taskObj as? URLSessionTask {
                LProFeedCapture.noteRequest(task.currentRequest ?? task.originalRequest)
            }
            orig(taskObj, sel)
        }
        method_setImplementation(method, imp_implementationWithBlock(block))
        LProLog.write("[capture] request capture on -[\(taskClass) resume]")
    }

    private static func noteRequest(_ request: URLRequest?) {
        guard runtimeEnabled, !capped, let request, let url = request.url?.absoluteString else { return }
        let lower = url.lowercased()
        guard urlNeedles.contains(where: { lower.contains($0) }) else { return }
        let method = request.httpMethod ?? "GET"
        let headers = request.allHTTPHeaderFields ?? [:]
        let bodyData = request.httpBody
        queue.async {
            guard !capped else { return }
            var lines = "headers: \(headers)"
            if let bodyData, !bodyData.isEmpty {
                let slice = bodyData.count > perRequestBodyCap ? bodyData.prefix(perRequestBodyCap) : bodyData
                let body = String(data: slice, encoding: .utf8) ?? "(non-UTF8 \(bodyData.count) bytes)"
                lines += "\nbody: \(body)"
            }
            appendRecord("REQ \(stamp()) \(method) \(url)", lines)
        }
    }

    // MARK: - responses (network body)

    // The SDUI feed decodes its responses with Swift JSONDecoder, not
    // NSJSONSerialization, so the JSON swizzle above never sees them. Capture the
    // response BODY at the network layer instead, observe-only (no request is ever
    // re-issued), two ways that together cover both session styles:
    //   - delegate-based sessions: swizzle the delegate's didReceiveData /
    //     didCompleteWithError (accumulate per task, flush on completion).
    //   - completion-based tasks: wrap the completion handler.
    private static var taskBufKey: UInt8 = 0
    private static var swizzledDelegateClasses = Set<ObjectIdentifier>()

    private static func responseURLWanted(_ url: String) -> Bool {
        let u = url.lowercased()
        return u.contains("/sdui/") || u.contains("voyagerfeed") || u.contains("feed.mainfeed")
            || u.contains("graphql") || u.contains("mainfeed")
    }

    private static func swizzleSessionFactory() {
        let sel = NSSelectorFromString("sessionWithConfiguration:delegate:delegateQueue:")
        guard let m = class_getClassMethod(URLSession.self, sel) else { return }
        typealias Fn = @convention(c) (AnyObject, Selector, AnyObject?, AnyObject?, AnyObject?) -> AnyObject?
        let orig = unsafeBitCast(method_getImplementation(m), to: Fn.self)
        let block: @convention(block) (AnyObject, AnyObject?, AnyObject?, AnyObject?) -> AnyObject? = { obj, config, delegate, queue in
            if let delegate { LProFeedCapture.swizzleDelegate(delegate) }
            return orig(obj, sel, config, delegate, queue)
        }
        method_setImplementation(m, imp_implementationWithBlock(block))
    }

    // Swizzle a session delegate's data/completion callbacks, once per class, only
    // where the class actually implements them (never add behaviour it lacked).
    private static func swizzleDelegate(_ delegateObj: AnyObject) {
        guard let cls: AnyClass = object_getClass(delegateObj) else { return }
        let id = ObjectIdentifier(cls)
        guard !swizzledDelegateClasses.contains(id) else { return }
        swizzledDelegateClasses.insert(id)

        let recvSel = NSSelectorFromString("URLSession:dataTask:didReceiveData:")
        if let m = class_getInstanceMethod(cls, recvSel) {
            typealias Fn = @convention(c) (AnyObject, Selector, AnyObject, AnyObject, NSData) -> Void
            let orig = unsafeBitCast(method_getImplementation(m), to: Fn.self)
            let block: @convention(block) (AnyObject, AnyObject, AnyObject, NSData) -> Void = { s, session, task, data in
                LProFeedCapture.appendTaskData(task, data as Data)
                orig(s, recvSel, session, task, data)
            }
            method_setImplementation(m, imp_implementationWithBlock(block))
        }
        let doneSel = NSSelectorFromString("URLSession:task:didCompleteWithError:")
        if let m = class_getInstanceMethod(cls, doneSel) {
            typealias Fn = @convention(c) (AnyObject, Selector, AnyObject, AnyObject, AnyObject?) -> Void
            let orig = unsafeBitCast(method_getImplementation(m), to: Fn.self)
            let block: @convention(block) (AnyObject, AnyObject, AnyObject, AnyObject?) -> Void = { s, session, task, err in
                LProFeedCapture.flushTask(task)
                orig(s, doneSel, session, task, err)
            }
            method_setImplementation(m, imp_implementationWithBlock(block))
        }
        LProLog.write("[capture] response capture armed on delegate \(cls)")
    }

    private static func taskBuffer(_ task: AnyObject) -> NSMutableData {
        if let d = objc_getAssociatedObject(task, &taskBufKey) as? NSMutableData { return d }
        let d = NSMutableData()
        objc_setAssociatedObject(task, &taskBufKey, d, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return d
    }

    private static func appendTaskData(_ task: AnyObject, _ data: Data) {
        guard runtimeEnabled, !capped else { return }
        let buf = taskBuffer(task)
        if buf.length < perResponseCap { buf.append(data) }
    }

    private static func flushTask(_ task: AnyObject) {
        guard let t = task as? URLSessionTask,
              let url = (t.currentRequest ?? t.originalRequest)?.url?.absoluteString else {
            objc_setAssociatedObject(task, &taskBufKey, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            return
        }
        let buf = taskBuffer(task)
        let data = buf as Data
        objc_setAssociatedObject(task, &taskBufKey, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        noteResponseBody(url: url, data: data)
    }

    // Wrap the completion-handler data-task factory on the concrete session class
    // (discovered at runtime), to catch completion-based responses.
    private static func swizzleCompletionHandler() {
        let probe = URLSession(configuration: .ephemeral)
        let cls: AnyClass = object_getClass(probe) ?? URLSession.self
        probe.invalidateAndCancel()
        let sel = NSSelectorFromString("dataTaskWithRequest:completionHandler:")
        guard let m = class_getInstanceMethod(cls, sel) else { return }
        typealias Fn = @convention(c) (AnyObject, Selector, AnyObject, @escaping @convention(block) (NSData?, AnyObject?, AnyObject?) -> Void) -> AnyObject
        let orig = unsafeBitCast(method_getImplementation(m), to: Fn.self)
        let block: @convention(block) (AnyObject, AnyObject, @escaping @convention(block) (NSData?, AnyObject?, AnyObject?) -> Void) -> AnyObject = { sess, req, handler in
            let wrapped: @convention(block) (NSData?, AnyObject?, AnyObject?) -> Void = { data, resp, err in
                if let data = data as Data?, let url = ((resp as? HTTPURLResponse)?.url ?? (req as? URLRequest)?.url)?.absoluteString {
                    LProFeedCapture.noteResponseBody(url: url, data: data)
                }
                handler(data, resp, err)
            }
            return orig(sess, sel, req, wrapped)
        }
        method_setImplementation(m, imp_implementationWithBlock(block))
    }

    private static func noteResponseBody(url: String, data: Data) {
        guard runtimeEnabled, !capped, data.count > 0, responseURLWanted(url) else { return }
        let slice = data.count > perResponseCap ? data.prefix(perResponseCap) : data
        let truncated = data.count > perResponseCap
        queue.async {
            guard !capped else { return }
            let body = String(data: slice, encoding: .utf8) ?? "(non-UTF8 \(data.count) bytes)"
            appendRecord("RESP \(stamp()) \(url) \(data.count)B\(truncated ? " (truncated)" : "")", body)
        }
    }

    // MARK: - file

    private static func stamp() -> String { String(format: "%.3f", Date().timeIntervalSince1970) }

    // Must be called on `queue`.
    private static func appendRecord(_ header: String, _ body: String) {
        let block = "===== \(header) =====\n\(body)\n\n"
        write(block)
    }

    private static func append(header: String) {
        queue.async { write("##### \(header) #####\n\n") }
    }

    // Must be called on `queue`.
    private static func write(_ text: String) {
        guard let url = fileURL(), let data = text.data(using: .utf8) else { return }
        if totalWritten + data.count > totalCap {
            if !capped {
                capped = true
                if let tail = "##### CAPTURE FULL (\(totalCap / 1_048_576) MB) - stopping #####\n".data(using: .utf8),
                   let h = try? FileHandle(forWritingTo: url) {
                    h.seekToEndOfFile(); h.write(tail); try? h.close()
                }
                LProLog.write("[capture] reached \(totalCap / 1_048_576) MB cap; stopped")
            }
            return
        }
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile(); h.write(data); try? h.close()
        } else {
            try? data.write(to: url, options: .atomic)
        }
        totalWritten += data.count
    }
}

extension UserDefaults {
    @UserDefault(key: "lproFeedCaptureEnabled", defaultValue: true)
    static var lproFeedCaptureEnabled: Bool
}
