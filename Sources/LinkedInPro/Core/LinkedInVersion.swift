import Foundation
import UIKit

// LinkedIn ships a DATE-STYLE version string (e.g. "2026.1021.1050"), not semver,
// with a separate CFBundleVersion (e.g. "9.32.5021"). Gate features on the
// short version compared as an integer tuple so chronological order holds as
// LinkedIn rolls 2026.10xx -> 2026.11xx. Prefer presence checks (see HookRegistry)
// over version numbers wherever possible; this is the fallback when a behavior
// genuinely changed at a known build.
enum LinkedInVersion {
    static let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    static let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""

    static var deviceModel: String {
        var sysinfo = utsname()
        uname(&sysinfo)
        return withUnsafePointer(to: &sysinfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
        }
    }

    // Splits on any non-digit so both "2026.1021.1050" and "9.32.5021" parse.
    static func parts(_ s: String) -> [Int] {
        s.split { !$0.isNumber }.compactMap { Int($0) }
    }

    // True when the running short version is >= the given date-style version.
    static func atLeast(_ other: String) -> Bool {
        !parts(short).lexicographicallyPrecedes(parts(other))
    }

    // True when min <= running short version <= max (inclusive).
    static func inRange(min: String, max: String) -> Bool {
        let v = parts(short)
        return !v.lexicographicallyPrecedes(parts(min)) && !parts(max).lexicographicallyPrecedes(v)
    }
}
