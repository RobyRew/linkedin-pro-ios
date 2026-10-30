import UIKit
import Foundation
import ObjectiveC.runtime

// SDUI JSON probe - a DevKit-only RE instrument, NOT a shipping feature.
//
// The SDUI feed is decoded by Swift-only classes (SDUI.Zen.ComponentCollectionViewModel
// has no ObjC methods), so there is no selector to hook between the JSON and the
// component tree. The one reachable boundary is NSJSONSerialization. To read the
// feed payload during reverse engineering we swizzle its class method and sample
// a handful of parses into the tweak log, so the sponsored marker can be named
// from live data. The parsed object is always returned unchanged.
//
// Three properties make this safe to carry in the source without taxing a normal
// install:
//   1. It only installs when DevKit is enabled (the console is already gated the
//      same way). A normal user's build never swizzles NSJSONSerialization at all.
//   2. The swizzle is REVERSIBLE: the original implementation is kept and restored,
//      so the hot JSON path returns to zero overhead afterwards.
//   3. It is SELF-LIMITING: once it has sampled enough (the log/raw caps below), it
//      restores the original implementation and removes itself. Sampling is a
//      one-shot during an RE session, not a permanent app-wide interposer.
//
// JSONObjectWithData:options:error: is a very hot path (every JSON parse in the
// whole app, LinkedIn's frameworks included), which is exactly why it must stay
// behind the DevKit gate and tear itself down when done.
enum SDUIPayloadProbe {
    private static var installed = false
    private static var logged = 0
    private static var rawHits = 0

    // Kept so the swizzle can be undone and the hot path restored.
    private static var hookedMethod: Method?
    private static var originalIMP: IMP?

    // Stop sampling (and uninstall) once both of these are satisfied.
    private static let logCap = 25
    private static let rawCap = 5

    static func install() {
        // DevKit-only: a normal build never interposes on NSJSONSerialization.
        guard LProDevKit.isEnabled else { return }
        guard !installed else { return }

        let sel = NSSelectorFromString("JSONObjectWithData:options:error:")
        guard let method = class_getClassMethod(JSONSerialization.self, sel) else { return }

        typealias Fn = @convention(c) (AnyObject, Selector, NSData, UInt,
                                       UnsafeMutablePointer<NSError?>?) -> AnyObject?
        let original = method_getImplementation(method)
        let orig = unsafeBitCast(original, to: Fn.self)

        let block: @convention(block) (AnyObject, NSData, UInt,
                                       UnsafeMutablePointer<NSError?>?) -> AnyObject? = { obj, data, opts, err in
            let result = orig(obj, sel, data, opts, err)
            SDUIPayloadProbe.observe(result, data: data)
            return result
        }
        method_setImplementation(method, imp_implementationWithBlock(block))

        hookedMethod = method
        originalIMP = original
        installed = true
        LProLog.write("[json] DevKit probe installed (self-uninstalls after \(logCap) parses / \(rawCap) raw hits)")
    }

    // Restore the original implementation; the hot JSON path returns to no overhead.
    static func uninstall() {
        guard installed, let method = hookedMethod, let imp = originalIMP else { return }
        method_setImplementation(method, imp)
        installed = false
        LProLog.write("[json] DevKit probe uninstalled (sampling complete)")
    }

    // One observation per parse. Cheap early-out until something is worth logging,
    // and a hard stop that tears the swizzle down once sampling is done.
    private static func observe(_ result: AnyObject?, data: NSData) {
        inspect(result, bytes: data.count)
        noteRawBytes(data)
        if logged >= logCap && rawHits >= rawCap { uninstall() }
    }

    // Early signal that the feed JSON passes through here at all, independent of
    // how it happens to be shaped after parsing.
    private static func noteRawBytes(_ data: NSData) {
        guard rawHits < rawCap, data.length > 2048 else { return }
        let needle = Data("componentKey".utf8)
        if (data as Data).range(of: needle) != nil {
            rawHits += 1
            LProLog.write("[json] raw \(data.length)B contains componentKey")
        }
    }

    private static func inspect(_ object: Any?, bytes: Int) {
        guard logged < logCap else { return }

        var sduiPath: [String] = []
        if let dict = object as? [String: Any] {
            findSDUIKeys(dict, path: "", into: &sduiPath, depth: 0)
        }

        // Log every large parse with its shape, so the feed payload can be
        // recognised even if it is not shaped like an SDUI document.
        if bytes >= 4096 || !sduiPath.isEmpty {
            logged += 1
            let kind = object.map { String(describing: type(of: $0)) } ?? "nil"
            var detail = ""
            if let dict = object as? [String: Any] {
                detail = "keys=\(Array(dict.keys.prefix(18)))"
            } else if let list = object as? [Any] {
                detail = "array[\(list.count)]"
            }
            LProLog.write("[json] #\(logged) \(bytes)B \(kind) \(detail)")
        }

        guard !sduiPath.isEmpty else { return }
        var hits: [String] = []
        if let dict = object as? [String: Any] { scan(dict, path: "", into: &hits, depth: 0) }
        LProLog.write("[json] SDUI keys at \(sduiPath.prefix(5))")
        LProLog.write("[json] flags: \(hits.prefix(40))")
    }

    private static func findSDUIKeys(_ any: Any, path: String, into out: inout [String], depth: Int) {
        guard depth < 5, out.count < 5 else { return }
        if let dict = any as? [String: Any] {
            for (key, value) in dict {
                if key == "rootComponent" || key == "componentKey" || key == "components" {
                    out.append(path.isEmpty ? key : "\(path).\(key)")
                }
                findSDUIKeys(value, path: path.isEmpty ? key : "\(path).\(key)", into: &out, depth: depth + 1)
            }
        } else if let list = any as? [Any] {
            for (i, value) in list.prefix(4).enumerated() {
                findSDUIKeys(value, path: "\(path)[\(i)]", into: &out, depth: depth + 1)
            }
        }
    }

    // Collects "path = value" for keys that look like sponsored/promoted markers.
    private static func scan(_ any: Any, path: String, into hits: inout [String], depth: Int) {
        guard depth < 8, hits.count < 40 else { return }
        if let dict = any as? [String: Any] {
            for (key, value) in dict {
                let lower = key.lowercased()
                let p = path.isEmpty ? key : "\(path).\(key)"
                if lower.contains("sponsor") || lower.contains("promot") || lower == "isad" {
                    hits.append("\(p)=\(String(describing: value).prefix(60))")
                }
                scan(value, path: p, into: &hits, depth: depth + 1)
            }
        } else if let list = any as? [Any] {
            for (i, value) in list.prefix(6).enumerated() {
                scan(value, path: "\(path)[\(i)]", into: &hits, depth: depth + 1)
            }
        }
    }
}
