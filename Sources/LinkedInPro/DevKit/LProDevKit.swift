import Foundation
import UIKit
import LinkedInProC

// DevKit: the on-device introspection console (Striker, from the striker
// submodule) plus, later, FLEX. Gated so RELEASE builds never open a listener.
//
// Enabled when ANY of:
//   - built with -DLPRO_DEVKIT, or
//   - a marker file `LPRO_DEVKIT` exists in the app's Documents dir (lets a
//     sideloaded build be armed without a rebuild - drop the file via Finder),
//   - the setting `lproDevKitEnabled` is on.
//
// The setting defaults ON (the console is loopback-only, reachable solely over a
// USB-forwarded port): an absent key means on, so only an explicit toggle-off in
// settings disables it. `setEnabled(_:)` writes that key and starts/stops the
// listener live, so the settings toggle takes effect without a relaunch.
enum LProDevKit {
    // A port distinct from MakeItPlay's Striker (45678) so both consoles can run
    // on one device without clashing. Reach it with `iproxy 45801 45801`.
    static let port: UInt16 = 45801
    static let defaultsKey = LProSettingsKeys.devKit

    static var isEnabled: Bool {
        #if LPRO_DEVKIT
        return true
        #else
        if let docs = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first,
           FileManager.default.fileExists(atPath: (docs as NSString).appendingPathComponent("LPRO_DEVKIT")) {
            return true
        }
        // Absent key -> default ON; respect an explicit stored value otherwise.
        if UserDefaults.standard.object(forKey: defaultsKey) == nil { return true }
        return UserDefaults.standard.bool(forKey: defaultsKey)
        #endif
    }

    static var isRunning: Bool { StrikerIsRunning() != 0 }

    private static var rearmObserver: NSObjectProtocol?

    static func startIfEnabled() {
        guard isEnabled else { return }
        StrikerStartOnPort(port)
        installForegroundRearm()
        LProLog.write("[devkit] Striker console on 127.0.0.1:\(port) - bridge with `iproxy \(port) \(port)`")
    }

    // The loopback listener runs on a detached thread; iOS can tear its socket down
    // when the app is suspended, after which the console would be silent until a
    // relaunch. Re-arm on every foreground so it is reachable in each session.
    // Idempotent: StrikerStartOnPort is a no-op while it is already running.
    private static func installForegroundRearm() {
        guard rearmObserver == nil else { return }
        rearmObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            guard isEnabled, !isRunning else { return }
            StrikerStartOnPort(port)
            LProLog.write("[devkit] Striker re-armed on foreground (127.0.0.1:\(port))")
        }
    }

    // Persist the toggle and bring the listener up/down immediately.
    static func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: defaultsKey)
        if enabled {
            StrikerStartOnPort(port)
            LProLog.write("[devkit] Striker console started on 127.0.0.1:\(port)")
        } else {
            StrikerStop()
            LProLog.write("[devkit] Striker console stopped")
        }
    }
}
