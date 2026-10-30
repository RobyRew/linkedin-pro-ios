import Foundation

// The Liquid Glass opt-out must be flipped while UIKit configures the design
// system, which happens during dyld image loading - BEFORE the first run loop.
// Reading UserDefaults that early re-enters NSUserDefaults' own initialisation
// and aborts the launch (see b22), which is why the earlier fix gated the flip on
// the first run loop - by which point UIKit had already read the key, so the flip
// never took effect and the glass bar never appeared.
//
// This stores the preference as a plain marker FILE instead. Checking a file's
// existence is a stat() - no NSUserDefaults, no locks, no re-entrancy - so it is
// safe to read at dyld-load time, early enough for the flip to count. The nav-bar
// settings write the marker when the toggle changes, and Tweak.init re-syncs it
// from the stored preference on every launch so the two never drift.
enum LProGlassFlag {
    private static var markerPath: String? {
        guard let docs = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first
        else { return nil }
        return (docs as NSString).appendingPathComponent("LPRO_GLASS_ON")
    }

    // Safe to call during dyld load: a bare file-existence check.
    static var isOn: Bool {
        guard let path = markerPath else { return false }
        return FileManager.default.fileExists(atPath: path)
    }

    // Mirror the stored preference onto the marker. Called from the settings
    // toggle (takes effect on the next launch) and from Tweak.init at startup.
    static func set(_ on: Bool) {
        guard let path = markerPath else { return }
        if on {
            if !FileManager.default.fileExists(atPath: path) {
                FileManager.default.createFile(atPath: path, contents: nil)
            }
        } else {
            try? FileManager.default.removeItem(atPath: path)
        }
    }
}
