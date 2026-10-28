import Foundation
import LinkedInProC

// DevKit: the on-device introspection console (Striker, from the striker
// submodule) plus, later, FLEX. Gated so RELEASE builds never open a listener.
//
// Enabled when ANY of:
//   - built with -DLPRO_DEVKIT, or
//   - a marker file `LPRO_DEVKIT` exists in the app's Documents dir (lets a
//     sideloaded build be armed without a rebuild - drop the file via Finder),
//   - the hidden setting `lproDevKitEnabled` is on.
enum LProDevKit {
    // A port distinct from MakeItPlay's Striker (45678) so both consoles can run
    // on one device without clashing. Reach it with `iproxy 45801 45801`.
    private static let port: UInt16 = 45801

    static var isEnabled: Bool {
        #if LPRO_DEVKIT
        return true
        #else
        if let docs = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first,
           FileManager.default.fileExists(atPath: (docs as NSString).appendingPathComponent("LPRO_DEVKIT")) {
            return true
        }
        return UserDefaults.standard.bool(forKey: "lproDevKitEnabled")
        #endif
    }

    static func startIfEnabled() {
        guard isEnabled else { return }
        StrikerStartOnPort(port)
        LProLog.write("[devkit] Striker console on 127.0.0.1:\(port) - bridge with `iproxy \(port) \(port)`")
    }
}
