import UIKit
import Foundation
import ObjectiveC.runtime

// The SDUI feed is decoded by Swift-only classes (SDUI.Zen.ComponentCollectionViewModel
// has no ObjC methods), so there is no selector to hook between the JSON and the
// component tree. The boundary that IS reachable is NSJSONSerialization.
//
// Phase 1 (this file): observe. Every payload that looks like an SDUI document
// (top-level "componentKey" / "rootComponent" / "components") is summarised once
// into the tweak log - top-level keys plus any key whose name mentions a
// sponsored/promoted flag - so the real marker can be identified from live data.
// The parsed object is returned unchanged.
//
// Phase 2 (once the marker is known): rewrite the object on the way out.
enum SDUIPayloadProbe {
    private static var installed = false
    private static var logged = 0

    static func install() {
        guard !installed else { return }
        installed = true
        let sel = NSSelectorFromString("JSONObjectWithData:options:error:")
        guard let method = class_getClassMethod(JSONSerialization.self, sel) else { return }
        let types = method_getTypeEncoding(method)
        typealias Fn = @convention(c) (AnyObject, Selector, NSData, UInt,
                                       UnsafeMutablePointer<NSError?>?) -> AnyObject?
        let orig = unsafeBitCast(method_getImplementation(method), to: Fn.self)

        let block: @convention(block) (AnyObject, NSData, UInt,
                                       UnsafeMutablePointer<NSError?>?) -> AnyObject? = { obj, data, opts, err in
            let result = orig(obj, sel, data, opts, err)
            SDUIPayloadProbe.inspect(result, bytes: data.count)
            SDUIPayloadProbe.noteRawBytes(data)
            return result
        }
        method_setImplementation(method, imp_implementationWithBlock(block))
        LProLog.write("[json] installed JSON probe (all parses sampled)")
    }

    private static var rawHits = 0

    // Early signal that the feed JSON passes through here at all, independent of
    // how it happens to be shaped after parsing.
    static func noteRawBytes(_ data: NSData) {
        guard rawHits < 5, data.length > 2048 else { return }
        let needle = Data("componentKey".utf8)
        if (data as Data).range(of: needle) != nil {
            rawHits += 1
            LProLog.write("[json] raw \(data.length)B contains componentKey")
        }
    }

    private static func inspect(_ object: Any?, bytes: Int) {
        guard logged < 25 else { return }

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
