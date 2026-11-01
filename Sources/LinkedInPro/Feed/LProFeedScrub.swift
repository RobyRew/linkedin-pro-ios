import Foundation

// Request-level feed filter: strip sponsored posts from the feed's getPage protobuf
// response BEFORE the app decodes it, instead of hiding the rendered cell.
//
// Validated on captured feed bytes: the response is
//   top[field 3] (payload) -> [field 3] (content) -> [field 1]* (one per post),
// and a sponsored post's bytes contain "sponsoredContentV2" / "SponsoredUpdateServed".
// We drop those [field 1] sub-messages and re-serialize, preserving every other
// field byte-for-byte (header, the per-post state entries, order).
//
// Fail-safe by construction: any parse problem or unexpected shape returns nil and
// the caller ships the ORIGINAL bytes, so the feed can never be corrupted.
enum LProFeedScrub {
    static var isOn: Bool {
        // Read UserDefaults directly, not the main-thread cache: this is checked from
        // a network callback (off the main thread), once per feed load.
        let f = UserDefaults.lproFeedFilter
        return f.scrubRequests && f.hideSponsored
    }

    static func wants(url: String) -> Bool {
        let u = url.lowercased()
        return u.contains("/sdui/") && u.contains("getpage") && u.contains("feed")
    }

    private static let markers: [[UInt8]] = [
        Array("sponsoredContentV2".utf8), Array("SponsoredUpdateServed".utf8),
    ]

    private struct Field { let num: Int; let wire: Int; let start: Int; let end: Int; var rebuilt: [UInt8]? }

    // MARK: wire helpers

    private static func readVarint(_ b: [UInt8], _ i: inout Int, _ end: Int) -> UInt64? {
        var shift: UInt64 = 0, v: UInt64 = 0
        while i < end {
            let c = b[i]; i += 1
            v |= UInt64(c & 0x7f) << shift
            if c & 0x80 == 0 { return v }
            shift += 7
            if shift > 63 { return nil }
        }
        return nil
    }

    private static func writeVarint(_ value: UInt64) -> [UInt8] {
        var v = value, o: [UInt8] = []
        repeat { var byte = UInt8(v & 0x7f); v >>= 7; if v != 0 { byte |= 0x80 }; o.append(byte) } while v != 0
        return o
    }

    private static func tag(_ num: Int, _ wire: Int) -> [UInt8] { writeVarint(UInt64(num << 3 | wire)) }

    private static func parse(_ b: [UInt8], _ start: Int, _ end: Int) -> [Field]? {
        var i = start, out: [Field] = []
        while i < end {
            guard let key = readVarint(b, &i, end) else { return nil }
            let num = Int(key >> 3), wire = Int(key & 7)
            switch wire {
            case 0:
                let s = i; guard readVarint(b, &i, end) != nil else { return nil }
                out.append(Field(num: num, wire: 0, start: s, end: i, rebuilt: nil))
            case 2:
                guard let ln = readVarint(b, &i, end) else { return nil }
                let s = i, e = i + Int(ln); guard e <= end, e >= s else { return nil }
                i = e; out.append(Field(num: num, wire: 2, start: s, end: e, rebuilt: nil))
            case 5:
                guard i + 4 <= end else { return nil }
                out.append(Field(num: num, wire: 5, start: i, end: i + 4, rebuilt: nil)); i += 4
            case 1:
                guard i + 8 <= end else { return nil }
                out.append(Field(num: num, wire: 1, start: i, end: i + 8, rebuilt: nil)); i += 8
            default: return nil
            }
        }
        return i == end ? out : nil
    }

    private static func reserialize(_ fields: [Field], _ b: [UInt8]) -> [UInt8] {
        var o: [UInt8] = []
        for f in fields {
            o += tag(f.num, f.wire)
            if f.wire == 2 {
                let val = f.rebuilt ?? Array(b[f.start..<f.end])
                o += writeVarint(UInt64(val.count)); o += val
            } else {
                o += Array(b[f.start..<f.end])
            }
        }
        return o
    }

    private static func containsMarker(_ b: [UInt8], _ start: Int, _ end: Int) -> Bool {
        for m in markers where rangeContains(b, start, end, m) { return true }
        return false
    }

    private static func rangeContains(_ b: [UInt8], _ start: Int, _ end: Int, _ needle: [UInt8]) -> Bool {
        let n = needle.count; guard n > 0, end - start >= n else { return false }
        var i = start
        while i <= end - n {
            if b[i] == needle[0] {
                var k = 1
                while k < n, b[i + k] == needle[k] { k += 1 }
                if k == n { return true }
            }
            i += 1
        }
        return false
    }

    // MARK: scrub

    // Returns the scrubbed data + dropped count, or nil when nothing was removed /
    // on any error (the caller then uses the original bytes).
    static func scrub(_ data: Data) -> (data: Data, dropped: Int)? {
        let b = [UInt8](data)
        guard b.count > 8, let top = parse(b, 0, b.count) else { return nil }
        var dropped = 0, changed = false
        var newTop: [Field] = []
        for var f in top {
            if f.num == 3, f.wire == 2, let payload = parse(b, f.start, f.end) {
                var newPay: [Field] = []
                for var pf in payload {
                    if pf.num == 3, pf.wire == 2, let content = parse(b, pf.start, pf.end) {
                        var newContent: [Field] = []
                        for cf in content {
                            if cf.num == 1, cf.wire == 2, containsMarker(b, cf.start, cf.end) {
                                dropped += 1; changed = true; continue
                            }
                            newContent.append(cf)
                        }
                        pf.rebuilt = reserialize(newContent, b)
                    }
                    newPay.append(pf)
                }
                f.rebuilt = reserialize(newPay, b)
            }
            newTop.append(f)
        }
        guard changed else { return nil }
        return (Data(reserialize(newTop, b)), dropped)
    }
}
