import Orion
import UIKit
import LinkedInProC

// DevKit-only. Logs each view controller as it appears (to identify host screens)
// and, when LinkedIn's account panel (NavPanelAccount*) is on screen, dumps the
// whole key-window view + VC tree to the tweak log once - so the account-panel
// structure can be read back over USB without a live Striker session (the app
// suspends in the background, which makes live socket commands unreliable).
struct DevKitViewLogGroup: HookGroup {}

class LProViewAppearHook: ClassHook<UIViewController> {
    typealias Group = DevKitViewLogGroup

    func viewDidAppear(_ animated: Bool) {
        orig.viewDidAppear(animated)
        guard LProDevKit.isEnabled else { return }
        LProLog.write("[vc] \(NSStringFromClass(type(of: target)))")
        if !LProViewLogger.dumped && LProViewLogger.accountPanelVisible() {
            LProViewLogger.dumped = true
            let logPath = (NSTemporaryDirectory() as NSString).appendingPathComponent("linkedinpro.log")
            StrikerDumpKeyWindow(logPath)
            LProLog.write("[devkit] dumped account-panel view tree to the log")
        }
    }
}

enum LProViewLogger {
    static var dumped = false

    static func accountPanelVisible() -> Bool {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
        return windows.contains { containsNavPanel($0) }
    }

    private static func containsNavPanel(_ view: UIView) -> Bool {
        if NSStringFromClass(type(of: view)).contains("NavPanelAccount") { return true }
        return view.subviews.contains { containsNavPanel($0) }
    }
}
