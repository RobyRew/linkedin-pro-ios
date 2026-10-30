import Foundation
import UIKit
import LinkedInProC

// DevKit: the on-device introspection console (Striker, from the striker
// submodule).
//
// The Striker console has an on/off switch in settings (default ON). When on it
// starts at launch and re-arms on every foreground; the toggle starts/stops it
// live. It is loopback-only (127.0.0.1), reachable solely over a USB-forwarded
// port, and answers only while LinkedIn is in the foreground.
//
// Precedence: a build compiled with -DLPRO_DEVKIT_OFF, or a `LPRO_DEVKIT_OFF`
// marker file in Documents, forces it off regardless of the toggle (a release
// escape hatch). Otherwise the stored toggle decides, defaulting on when unset.
enum LProDevKit {
    // A port distinct from MakeItPlay's Striker (45678) so both consoles can run
    // on one device without clashing. Reach it with `iproxy 45801 45801`.
    static let port: UInt16 = 45801
    private static let defaultsKey = "lproDevKitEnabled"

    static var isEnabled: Bool {
        #if LPRO_DEVKIT_OFF
        return false
        #else
        if let docs = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first,
           FileManager.default.fileExists(atPath: (docs as NSString).appendingPathComponent("LPRO_DEVKIT_OFF")) {
            return false
        }
        // Absent key -> default ON; otherwise respect the stored toggle.
        if UserDefaults.standard.object(forKey: defaultsKey) == nil { return true }
        return UserDefaults.standard.bool(forKey: defaultsKey)
        #endif
    }

    static var isRunning: Bool { StrikerIsRunning() != 0 }

    private static var rearmObserver: NSObjectProtocol?

    static func startIfEnabled() {
        guard isEnabled else {
            LProLog.write("[devkit] Striker off (toggle/LPRO_DEVKIT_OFF)")
            return
        }
        StrikerStartOnPort(port)
        installForegroundRearm()
        LProLog.write("[devkit] Striker console on 127.0.0.1:\(port) - bridge with `iproxy \(port) \(port)`")
    }

    // Settings toggle: persist and bring the listener up/down immediately.
    static func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: defaultsKey)
        if enabled {
            StrikerStartOnPort(port)
            installForegroundRearm()
            LProLog.write("[devkit] Striker started (toggle on)")
        } else {
            StrikerStop()
            LProLog.write("[devkit] Striker stopped (toggle off)")
        }
    }

    // The loopback listener runs on a detached thread; iOS can tear its socket down
    // when the app is suspended, and a launch that never reaches the foreground can
    // suspend before the initial bind completes. Re-arm on every foreground so the
    // console is reachable in each session. Idempotent: StrikerStartOnPort is a
    // no-op while it is already running, and the guard re-binds only when it is not.
    private static func installForegroundRearm() {
        guard rearmObserver == nil else { return }
        rearmObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            guard isEnabled, !isRunning else { return }
            StrikerStartOnPort(port)
            LProLog.write("[devkit] Striker re-armed on foreground (127.0.0.1:\(port))")
        }
    }
}
