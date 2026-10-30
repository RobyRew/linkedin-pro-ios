import Foundation
import UIKit
import LinkedInProC

// DevKit: the on-device introspection console (Striker, from the striker
// submodule).
//
// This is a research tweak, so the console is FUNCTIONAL ALWAYS: it starts on
// every launch and re-arms on every foreground, and no stored setting can leave
// it off. An earlier design gated it on `lproDevKitEnabled`, whose off-state
// persisted across launches (and across a build upgrade) and could silently keep
// the console down - exactly the failure that makes "always functional" untrue.
// That runtime switch is gone.
//
// Escape hatches, for a build that must ship with no listener at all:
//   - compile with -DLPRO_DEVKIT_OFF (the console is compiled out of the gate), or
//   - drop a `LPRO_DEVKIT_OFF` marker file in the app's Documents (runtime opt-out,
//     e.g. via Finder file sharing) and relaunch.
//
// The console is loopback-only (127.0.0.1), reachable solely over a USB-forwarded
// port, and answers only while LinkedIn is in the foreground.
enum LProDevKit {
    // A port distinct from MakeItPlay's Striker (45678) so both consoles can run
    // on one device without clashing. Reach it with `iproxy 45801 45801`.
    static let port: UInt16 = 45801

    static var isEnabled: Bool {
        #if LPRO_DEVKIT_OFF
        return false
        #else
        // Runtime opt-out: a marker file disables the console without a rebuild.
        if let docs = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first,
           FileManager.default.fileExists(atPath: (docs as NSString).appendingPathComponent("LPRO_DEVKIT_OFF")) {
            return false
        }
        return true
        #endif
    }

    static var isRunning: Bool { StrikerIsRunning() != 0 }

    private static var rearmObserver: NSObjectProtocol?

    static func startIfEnabled() {
        guard isEnabled else {
            LProLog.write("[devkit] Striker disabled (LPRO_DEVKIT_OFF)")
            return
        }
        StrikerStartOnPort(port)
        installForegroundRearm()
        LProLog.write("[devkit] Striker console on 127.0.0.1:\(port) - bridge with `iproxy \(port) \(port)`")
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
