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

// Earlier than viewDidAppear, in case the bar's own gesture recognizers are in
// place by then. Idempotent with the appear hook.
class TabEngineDidLoadHook: ClassHook<UITabBarController> {
    typealias Group = TabEngineGroup
    static let targetName = "LINMainNavViewController"

    func viewDidLoad() {
        orig.viewDidLoad()
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
        gesture.minimumPressDuration = 0.5
        gesture.allowableMovement = 12
        gesture.cancelsTouchesInView = false
        // Let it run alongside the bar's own recognizers instead of losing the
        // race to the tab-select gesture.
        gesture.delegate = LProTabLongPress.shared
        bar.addGestureRecognizer(gesture)
        LProLog.write("[navbar] long-press installed on \(NSStringFromClass(type(of: bar)))")
    }

    // UIKit shows at most five items; anything beyond goes to the More list.
    static let maxVisibleTabs = 5

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

    // Returns true when the bar was changed. On iOS 18+ it reorders the modern
    // UITab collection in place (preserving identity); otherwise, and whenever an
    // extra tab must be built, it rebuilds viewControllers.
    @discardableResult
    static func apply() -> Bool {
        guard let tbc = tabBarController else {
            LProLog.write("[navbar] apply: no tab bar controller captured yet")
            return false
        }
        let opt = UserDefaults.lproTabBar

        if #available(iOS 18.0, *), opt.extraTabs.isEmpty, !tbc.tabs.isEmpty {
            return applyModern(tbc, opt)
        }
        return applyLegacy(tbc, opt)
    }

    // iOS 18+: reorder / hide the existing UITab objects in place. Reusing the same
    // UITab instances (never new ones) keeps each tab's identifier, LinkedIn's
    // selection and state restoration, and the system More overflow - all of which
    // a viewControllers rebuild would discard.
    @available(iOS 18.0, *)
    private static func applyModern(_ tbc: UITabBarController, _ opt: TabBarOptions) -> Bool {
        let current = tbc.tabs
        let named: [(name: String, value: UITab)] = current.map { tab in
            (name: resolvedName(title: tab.title, viewController: tab.viewController,
                                identifier: tab.identifier, discovered: opt.discoveredTabs),
             value: tab)
        }
        let visible = arrange(named, order: opt.order).filter { !opt.hiddenTabs.contains($0.name) }
        guard !visible.isEmpty else {
            LProLog.write("[navbar] apply(modern): refusing to remove every tab")
            return false
        }
        let target = visible.map { $0.value }
        if target.count == current.count, zip(target, current).allSatisfy({ $0.0 === $0.1 }) {
            return false  // already matches
        }
        let selected = tbc.selectedTab
        tbc.tabs = target
        if let selected, target.contains(where: { $0 === selected }) {
            tbc.selectedTab = selected
        }
        LProLog.write("[navbar] applied (modern UITab): \(visible.map { $0.name })")
        return true
    }

    private static func applyLegacy(_ tbc: UITabBarController, _ opt: TabBarOptions) -> Bool {
        guard let current = tbc.viewControllers, !current.isEmpty else {
            LProLog.write("[navbar] apply: no view controllers captured yet")
            return false
        }
        let selected = tbc.selectedIndex

        var named: [(name: String, value: UIViewController)] = current.map { vc in
            (name: resolvedName(title: vc.tabBarItem.title, viewController: vc,
                                identifier: nil, discovered: opt.discoveredTabs),
             value: vc)
        }

        // Extras that were never built in this run: build them now.
        for selector in opt.extraTabs {
            let known = opt.extraTabNames[selector]
            if let known, named.contains(where: { $0.name == known }) { continue }
            guard let built = makeTab(selector: selector) else {
                LProLog.write("[navbar] apply: cannot build \(selector) yet")
                continue
            }
            if named.contains(where: { $0.name == built.name }) { continue }
            named.append((name: built.name, value: built.vc))
        }

        let visible = arrange(named, order: opt.order).filter { !opt.hiddenTabs.contains($0.name) }
        guard !visible.isEmpty else {
            LProLog.write("[navbar] apply: refusing to remove every tab")
            return false
        }
        let target = visible.map { $0.value }
        if target.count == current.count, zip(target, current).allSatisfy({ $0.0 === $0.1 }) {
            return false  // already matches
        }
        tbc.setViewControllers(target, animated: false)
        if selected < target.count { tbc.selectedIndex = selected }
        LProLog.write("[navbar] applied (viewControllers): \(visible.map { $0.name })")
        return true
    }

    // Shared ordering: the user's order first (de-duplicated), then anything not
    // named in that list, in its original relative position - so a tab that could
    // not be named is still kept and never silently dropped.
    private static func arrange<T>(_ named: [(name: String, value: T)],
                                   order desiredOrder: [String]) -> [(name: String, value: T)] {
        var out: [(name: String, value: T)] = []
        var seen = Set<String>()
        for name in desiredOrder where !seen.contains(name) {
            if let hit = named.first(where: { $0.name == name }) { out.append(hit); seen.insert(name) }
        }
        for entry in named where !seen.contains(entry.name) {
            out.append(entry); seen.insert(entry.name)
        }
        return out
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

    // LinkedIn shows bar titles ("Home", "My Network") that differ from the tabName
    // ("Feed", "MyNetwork"); matching is on a normalized form against the names
    // discovered at launch. Resolution falls back through the tab's identifier and
    // its view-controller class so a blanked title (icon-only mode) still resolves,
    // and always returns a non-empty name so a tab is never dropped.
    static func resolvedName(title: String?, viewController: UIViewController?,
                             identifier: String?, discovered: [String]) -> String {
        if let byTitle = canonicalName(forToken: title, discovered: discovered) { return byTitle }
        if let byID = canonicalName(forToken: identifier, discovered: discovered) { return byID }
        if let vc = viewController, let byClass = canonicalName(fromClass: vc, discovered: discovered) {
            return byClass
        }
        // Last resort: a stable per-tab name that will not match order / hidden, so
        // the tab keeps its place and stays visible.
        if let title, !title.isEmpty { return title }
        if let vc = viewController { return NSStringFromClass(type(of: vc)) }
        return (identifier?.isEmpty == false) ? identifier! : "tab"
    }

    private static func canonicalName(forToken token: String?, discovered: [String]) -> String? {
        guard let token, !token.isEmpty else { return nil }
        let t = TabCatalog.normalized(token)
        guard !t.isEmpty else { return nil }
        if t == "home" { return discovered.first(where: { TabCatalog.normalized($0) == "feed" }) ?? "Feed" }
        if let hit = discovered.first(where: { TabCatalog.normalized($0) == t }) { return hit }
        return alias(for: t, discovered: discovered)
    }

    // Icon-only mode blanks the title, so fall back to the view-controller's class
    // name, which contains a known tab token (e.g. "...FeedTab...").
    private static func canonicalName(fromClass vc: UIViewController, discovered: [String]) -> String? {
        let classNames = ([vc] + vc.children).map { NSStringFromClass(type(of: $0)).lowercased() }
        for tab in discovered {
            let token = TabCatalog.normalized(tab)
            if token.count >= 4, classNames.contains(where: { $0.contains(token) }) { return tab }
        }
        for (token, canon) in classAliases where classNames.contains(where: { $0.contains(token) }) {
            return discovered.first(where: { TabCatalog.normalized($0) == TabCatalog.normalized(canon) }) ?? canon
        }
        return nil
    }

    private static let classAliases: [(token: String, canon: String)] = [
        ("feed", "Feed"), ("home", "Feed"), ("mynetwork", "MyNetwork"),
        ("network", "MyNetwork"), ("notification", "Notifications"), ("notif", "Notifications"),
        ("messag", "Messaging"), ("job", "Jobs"), ("more", "More"),
    ]

    private static func alias(for normalizedToken: String, discovered: [String]) -> String? {
        for (token, canon) in classAliases where normalizedToken.contains(token) {
            return discovered.first(where: { TabCatalog.normalized($0) == TabCatalog.normalized(canon) }) ?? canon
        }
        return nil
    }

    static func index(of name: String, in tbc: UITabBarController) -> Int? {
        let discovered = UserDefaults.lproTabBar.discoveredTabs
        if #available(iOS 18.0, *), !tbc.tabs.isEmpty {
            for (i, tab) in tbc.tabs.enumerated() where resolvedName(
                title: tab.title, viewController: tab.viewController,
                identifier: tab.identifier, discovered: discovered) == name {
                return i
            }
        }
        guard let vcs = tbc.viewControllers else { return nil }
        for (i, vc) in vcs.enumerated() where resolvedName(
            title: vc.tabBarItem.title, viewController: vc,
            identifier: nil, discovered: discovered) == name {
            return i
        }
        return nil
    }
}

// Opens the tweak settings when the FIRST bar item is long-pressed. Works with
// both the classic UITabBarButton and iOS 26's floating _UITabButton; it also
// accepts a press inside the left-most item's frame, because the floating bar
// nests its buttons several levels deep and a hit test may land on an inner
// label that is not itself a button.
final class LProTabLongPress: NSObject, UIGestureRecognizerDelegate {
    static let shared = LProTabLongPress()

    func gestureRecognizer(_ gesture: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }

    @objc func handle(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began, UserDefaults.lproTabBar.longPressEntry,
              let bar = gesture.view else { return }

        let point = gesture.location(in: bar)
        let hit = bar.hitTest(point, with: nil)
        let buttons = tabButtons(in: bar).sorted {
            $0.convert($0.bounds, to: bar).minX < $1.convert($1.bounds, to: bar).minX
        }
        let hitButton = hit.flatMap { tabButton(containing: $0, in: bar) }
        let firstFrame = buttons.first.map { $0.convert($0.bounds, to: bar) }
        let onFirst = (hitButton != nil && hitButton === buttons.first)
            || (firstFrame?.insetBy(dx: -8, dy: -8).contains(point) ?? false)

        LProLog.write("[navbar] long press at \(Int(point.x)),\(Int(point.y)) "
                      + "hit=\(hit.map { NSStringFromClass(type(of: $0)) } ?? "nil") "
                      + "buttons=\(buttons.count) first=\(onFirst)")

        guard onFirst else { return }
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
