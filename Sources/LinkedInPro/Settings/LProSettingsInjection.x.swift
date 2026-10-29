import Orion
import UIKit
import Foundation

// Entry point into the tweak's settings screen.
//
// Version-independent strategy: hook the stable UIKit selector
// -[UINavigationController pushViewController:animated:] and, when LinkedIn
// pushes its own Settings screen, add a nav-bar button that opens our screen.
// This binds NO LinkedIn class, so it survives LinkedIn's Swift/server-driven
// settings rewrites.
//
// A tighter "row directly above the Settings item" in the HomeNav account panel
// (NavPanelAccountLinksView -didTapSettings) is the intended refinement; it needs
// an on-device Striker pass to confirm how that Swift panel builds its rows.

struct SettingsInjectionGroup: HookGroup {}

// Localized titles LinkedIn's main Settings screen uses. Matched to detect the
// screen without binding its (Swift) class name. Extend per locale.
private let lproSettingsTitles: Set<String> = [
    "Settings", "Settings & Privacy", "Settings & privacy", "Settings and Privacy",
]

private let lproButtonTag = 0x4C50  // 'LP'

// Opens the tweak settings screen on whatever navigation stack is in front.
final class LProSettingsOpener: NSObject {
    static let shared = LProSettingsOpener()

    @objc func open() {
        let host = LProSettingsViewController()
        guard let top = WindowHelper.topViewController else {
            LProLog.write("[settings] open: no top view controller")
            return
        }
        if let nav = top.navigationController {
            nav.pushViewController(host, animated: true)
            LProLog.write("[settings] pushed onto \(NSStringFromClass(type(of: nav)))")
        } else {
            // The Me-tab account panel has no navigation controller, so present
            // modally wrapped in one (title + Done button).
            let nav = UINavigationController(rootViewController: host)
            host.navigationItem.leftBarButtonItem = UIBarButtonItem(
                barButtonSystemItem: .done, target: LProSettingsOpener.shared,
                action: #selector(dismissSettings))
            top.present(nav, animated: true)
            LProLog.write("[settings] presented modally from \(NSStringFromClass(type(of: top)))")
        }
    }

    @objc func dismissSettings() {
        var vc = WindowHelper.keyWindow?.rootViewController
        while let presented = vc?.presentedViewController { vc = presented }
        vc?.dismiss(animated: true)
    }
}

// True when `vc` looks like LinkedIn's own Settings screen (and not ours).
private func lproIsSettings(_ vc: UIViewController) -> Bool {
    let name = NSStringFromClass(type(of: vc))
    if name.contains("LinkedInPro") || name.contains("LProSettings") { return false }
    if let title = vc.navigationItem.title ?? vc.title, lproSettingsTitles.contains(title) { return true }
    return name.contains("SettingsViewController") && !name.contains("Dev") && !name.contains("Job")
}

// Adds our nav-bar button to a Settings VC (idempotent via the item tag). A free
// function, deliberately outside the ClassHook so Orion does not register it as
// an ObjC method on UINavigationController.
private func lproInjectButton(into vc: UIViewController) {
    let existing = (vc.navigationItem.rightBarButtonItems ?? []) + (vc.navigationItem.leftBarButtonItems ?? [])
    if existing.contains(where: { $0.tag == lproButtonTag }) { return }
    let item = UIBarButtonItem(image: UIImage(systemName: "slider.horizontal.3"),
                               style: .plain,
                               target: LProSettingsOpener.shared,
                               action: #selector(LProSettingsOpener.open))
    item.tag = lproButtonTag
    item.accessibilityLabel = "LinkedIn Professional"
    vc.navigationItem.rightBarButtonItems = [item] + (vc.navigationItem.rightBarButtonItems ?? [])
    LProLog.write("[settings] injected entry into \(NSStringFromClass(type(of: vc)))")
}

class SettingsNavHook: ClassHook<UINavigationController> {
    typealias Group = SettingsInjectionGroup

    func pushViewController(_ viewController: UIViewController, animated: Bool) {
        orig.pushViewController(viewController, animated: animated)
        // Defer so the pushed VC's viewDidLoad has set its title/navigationItem.
        DispatchQueue.main.async {
            if lproIsSettings(viewController) { lproInjectButton(into: viewController) }
        }
    }
}
