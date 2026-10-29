import Orion
import UIKit
import Foundation
import ObjectiveC.runtime

// Runtime tab control. Earlier builds rewrote MainNavTabTypeFactory.mainNavTabsOrder,
// which only runs once at launch (the order is cached), so a change needed a
// relaunch. This engine instead works on the live UITabBarController:
//   - it captures the controller, LinkedIn's tab-type factory and its VC factory
//     from hooks that already run at launch;
//   - apply() rebuilds tbc.viewControllers from the user's order / hidden set /
//     extras and calls setViewControllers:animated:false - no relaunch;
//   - a long press on the FIRST tab opens the tweak settings.
// Every call is guarded: if a factory is not captured yet, the change stays on
// the relaunch path (mainNavTabsOrder still applies it next launch).
struct TabEngineGroup: HookGroup {}

class TabEngineAppearHook: ClassHook<UITabBarController> {
    typealias Group = TabEngineGroup
    static let targetName = "LINMainNavViewController"

    func viewDidAppear(_ animated: Bool) {
        orig.viewDidAppear(animated)
        TabEngine.attach(target)
    }
}

// Captures the VC factory (its -makeViewControllerForTabType: is what builds a
// tab's controller) so an added tab can be created at runtime.
class TabVCFactoryHook: ClassHook<NSObject> {
    typealias Group = TabEngineGroup
    static let targetName = "LINMainNavTabBarViewControllerFactory"

    func makeViewControllerForTabType(_ tabType: Any?) -> UIViewController? {
        TabEngine.vcFactory = target
        return orig.makeViewControllerForTabType(tabType)
    }
}

enum TabEngine {
    static weak var tabBarController: UITabBarController?
    static weak var typeFactory: NSObject?
    static weak var vcFactory: NSObject?

    private static var longPressInstalled = false
    private static var didApplyDefault = false

    static func attach(_ tbc: UITabBarController) {
        tabBarController = tbc
        installLongPress(on: tbc)
        applyAppearance()
        applyDefaultTabIfNeeded()
    }

    // Dark bar only: overrides the appearance of the tab bar view, not the app.
    static func applyAppearance() {
        guard let tbc = tabBarController else { return }
        let dark = UserDefaults.lproTabBar.darkTabBar
        let style: UIUserInterfaceStyle = dark ? .dark : .unspecified
        if tbc.tabBar.overrideUserInterfaceStyle != style {
            tbc.tabBar.overrideUserInterfaceStyle = style
        }
    }

    // MARK: - long press on the first tab

    private static func installLongPress(on tbc: UITabBarController) {
        guard !longPressInstalled else { return }
        let bar = tbc.tabBar
        longPressInstalled = true
        let gesture = UILongPressGestureRecognizer(target: LProTabLongPress.shared,
                                                   action: #selector(LProTabLongPress.handle(_:)))
        gesture.minimumPressDuration = 0.55
        gesture.cancelsTouchesInView = false
        bar.addGestureRecognizer(gesture)
        LProLog.write("[navbar] long-press installed on the tab bar")
    }

    // MARK: - default launch tab

    static func applyDefaultTabIfNeeded() {
        guard !didApplyDefault else { return }
        let name = UserDefaults.lproTabBar.defaultTab
        guard !name.isEmpty else { return }
        didApplyDefault = true
        // After LinkedIn's own selection has settled.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            guard let tbc = tabBarController, let index = index(of: name, in: tbc) else { return }
            if tbc.selectedIndex != index {
                tbc.selectedIndex = index
                LProLog.write("[navbar] selected default tab \(name) at \(index)")
            }
        }
    }

    // MARK: - dynamic apply

    // Returns true when the bar was rebuilt.
    @discardableResult
    static func apply() -> Bool {
        guard let tbc = tabBarController, let current = tbc.viewControllers, !current.isEmpty else {
            LProLog.write("[navbar] apply: no tab bar controller captured yet")
            return false
        }
        let opt = UserDefaults.lproTabBar
        let selected = tbc.selectedIndex

        var named: [(name: String, vc: UIViewController)] = []
        for vc in current {
            guard let n = canonicalName(for: vc, discovered: opt.discoveredTabs) else { continue }
            named.append((n, vc))
        }
        guard !named.isEmpty else { return false }

        // Extras that were never built in this run: build them now.
        for selector in opt.extraTabs {
            let known = opt.extraTabNames[selector]
            if let known, named.contains(where: { $0.name == known }) { continue }
            guard let built = makeTab(selector: selector) else {
                LProLog.write("[navbar] apply: cannot build \(selector) yet")
                continue
            }
            if named.contains(where: { $0.name == built.name }) { continue }
            named.append(built)
        }

        var ordered: [(name: String, vc: UIViewController)] = []
        var seen = Set<String>()
        for name in opt.order where !seen.contains(name) {
            if let hit = named.first(where: { $0.name == name }) { ordered.append(hit); seen.insert(name) }
        }
        for entry in named where !seen.contains(entry.name) {
            ordered.append(entry); seen.insert(entry.name)
        }

        let visible = ordered.filter { !opt.hiddenTabs.contains($0.name) }
        guard !visible.isEmpty else {
            LProLog.write("[navbar] apply: refusing to remove every tab")
            return false
        }

        let target = visible.map { $0.vc }
        if target.count == current.count, zip(target, current).allSatisfy({ $0.0 === $0.1 }) {
            return false  // already matches
        }

        tbc.setViewControllers(target, animated: false)
        if selected < target.count { tbc.selectedIndex = selected }
        LProLog.write("[navbar] applied dynamically: \(visible.map { $0.name })")
        return true
    }

    // Builds a tab's controller through LinkedIn's own factories: the type comes
    // from MainNavTabTypeFactory, the controller from the VC factory captured by
    // TabVCFactoryHook. Returns the controller with its real tabName.
    static func makeTab(selector: String) -> (name: String, vc: UIViewController)? {
        guard let typeFactory,
              let type = TabCatalog.tabType(selector: selector, factory: typeFactory),
              let vcFactory,
              vcFactory.responds(to: NSSelectorFromString("makeViewControllerForTabType:")),
              let unmanaged = vcFactory.perform(NSSelectorFromString("makeViewControllerForTabType:"), with: type),
              let vc = unmanaged.takeUnretainedValue() as? UIViewController else { return nil }
        return (TabCatalog.tabName(type), vc)
    }

    // MARK: - naming

    // LinkedIn's bar titles ("Home", "My Network") vs tabName ("Feed",
    // "MyNetwork"): match on a normalized form and the names discovered at launch.
    static func canonicalName(for vc: UIViewController, discovered: [String]) -> String? {
        guard let title = vc.tabBarItem.title, !title.isEmpty else { return nil }
        let t = TabCatalog.normalized(title)
        if t == "home" { return discovered.first(where: { TabCatalog.normalized($0) == "feed" }) ?? "Feed" }
        return discovered.first(where: { TabCatalog.normalized($0) == t }) ?? title
    }

    static func index(of name: String, in tbc: UITabBarController) -> Int? {
        guard let vcs = tbc.viewControllers else { return nil }
        let discovered = UserDefaults.lproTabBar.discoveredTabs
        for (i, vc) in vcs.enumerated() where canonicalName(for: vc, discovered: discovered) == name {
            return i
        }
        return nil
    }
}

// Opens the tweak settings when the FIRST bar item is long-pressed. Works with
// both the classic UITabBarButton and iOS 26's floating _UITabButton.
final class LProTabLongPress: NSObject {
    static let shared = LProTabLongPress()

    @objc func handle(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began, UserDefaults.lproTabBar.longPressEntry,
              let bar = gesture.view else { return }
        let point = gesture.location(in: bar)
        guard let hit = bar.hitTest(point, with: nil),
              let button = tabButton(containing: hit, in: bar) else { return }
        let buttons = tabButtons(in: bar).sorted {
            $0.convert($0.bounds, to: bar).minX < $1.convert($1.bounds, to: bar).minX
        }
        guard buttons.first === button else { return }
        LProLog.write("[navbar] long press on the first tab -> settings")
        LProSettingsOpener.shared.open()
    }

    private func tabButton(containing view: UIView, in bar: UIView) -> UIView? {
        var current: UIView? = view
        while let v = current, v !== bar {
            if NSStringFromClass(type(of: v)).contains("TabButton") { return v }
            current = v.superview
        }
        return nil
    }

    private func tabButtons(in view: UIView) -> [UIView] {
        var out: [UIView] = []
        if NSStringFromClass(type(of: view)).contains("TabButton") { out.append(view) }
        for sub in view.subviews { out += tabButtons(in: sub) }
        return out
    }
}
