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
            SDUIPayloadProbe.inspect(result)
            return result
        }
        method_setImplementation(method, imp_implementationWithBlock(block))
        LProLog.write("[json] installed SDUI payload probe")
    }

    private static func inspect(_ object: Any?) {
        guard logged < 4 else { return }
        guard let dict = object as? [String: Any] else { return }
        guard dict["rootComponent"] != nil || dict["components"] != nil || dict["componentKey"] != nil
        else { return }
        logged += 1

        let keys = dict.keys.sorted()
        var hits: [String] = []
        scan(dict, path: "", into: &hits, depth: 0)
        LProLog.write("[json] SDUI payload #\(logged) keys=\(keys.prefix(25))")
        LProLog.write("[json] flags: \(hits.prefix(40))")
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
