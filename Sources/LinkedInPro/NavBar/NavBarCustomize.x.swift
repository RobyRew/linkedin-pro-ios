import Orion
import UIKit
import Foundation

// Phase 3, nav bar. LINMainNavViewController is a UITabBarController, so:
//   - icon-only tabs: blank each item's title (LINTabBarItemFactory).
//   - reorder: rewrite the ordered tab list (MainNavTabTypeFactory.mainNavTabsOrder)
//     to the user's permutation (reorder only; never drop a tab - the app may
//     assume a fixed set).
//   - iOS 26 floating-glass tabs: LinkedIn opts out of the iOS 26 design system
//     via Info.plist UIDesignRequiresCompatibility=1; flipping that to false for
//     the main bundle lets the system render the Liquid Glass "island" tab bar.
//     App-wide and experimental, so it is behind a default-off toggle, installed
//     early (before UIKit reads the key). See GlassTabsGroup.
struct NavBarCustomizeGroup: HookGroup {}

// Icon-only tabs: blank the returned item's title + nudge the icon to centre.
class TabBarItemFactoryHook: ClassHook<NSObject> {
    typealias Group = NavBarCustomizeGroup
    static let targetName = "LINTabBarItemFactory"

    func makeTabBarItemForTabType(_ tabType: Any?) -> UITabBarItem? {
        let item = orig.makeTabBarItemForTabType(tabType)
        guard UserDefaults.lproTabBar.hideLabels, let item = item else { return item }
        item.title = ""
        item.imageInsets = UIEdgeInsets(top: 6, left: 0, bottom: -6, right: 0)
        return item
    }
}

// Reorder the bottom tabs. Called once (the order is cached), so a change takes
// effect on relaunch.
class MainNavTabsOrderHook: ClassHook<NSObject> {
    typealias Group = NavBarCustomizeGroup
    static let targetName = "_TtC14HomeNavAPIImpl21MainNavTabTypeFactory"

    func mainNavTabsOrder() -> NSArray {
        let original = orig.mainNavTabsOrder()
        return TabReorder.apply(original)
    }
}

enum TabReorder {
    static func apply(_ original: NSArray) -> NSArray {
        let items = original.compactMap { $0 as? NSObject }
        guard !items.isEmpty else { return original }

        let named = items.map { (name: tabName($0), obj: $0) }
        let names = named.map { $0.name }

        // Publish the natural order so the settings UI can list the real tabs.
        var opt = UserDefaults.lproTabBar
        if opt.discoveredTabs != names {
            opt.discoveredTabs = names
            UserDefaults.lproTabBar = opt
            LProLog.write("[navbar] tabs discovered: \(names)")
        }

        let order = opt.order
        guard !order.isEmpty else { return original }

        var result: [NSObject] = []
        for name in order {
            if let found = named.first(where: { $0.name == name })?.obj { result.append(found) }
        }
        for entry in named where !order.contains(entry.name) { result.append(entry.obj) }

        // Only a true permutation (same count) - never drop a tab.
        guard result.count == items.count else { return original }
        return result as NSArray
    }

    private static func tabName(_ obj: NSObject) -> String {
        if obj.responds(to: NSSelectorFromString("tabName")),
           let n = obj.value(forKey: "tabName") as? String { return n }
        return NSStringFromClass(type(of: obj))
    }
}

// iOS 26 floating-glass tab bar: flip the design opt-out for the main bundle.
// Hooks both the key accessor and the whole info dictionary so UIKit sees the
// flip whichever it reads. Installed early (Tweak.init) so it is in place before
// UIKit configures the design system at launch.
struct GlassTabsGroup: HookGroup {}

class BundleInfoHook: ClassHook<Bundle> {
    typealias Group = GlassTabsGroup
    private static let key = "UIDesignRequiresCompatibility"

    func object(forInfoDictionaryKey key: String) -> Any? {
        if key == Self.key, target === Bundle.main, UserDefaults.lproTabBar.iOS26GlassTabs {
            return false
        }
        return orig.object(forInfoDictionaryKey: key)
    }

    func infoDictionary() -> NSDictionary? {
        let dict = orig.infoDictionary()
        guard target === Bundle.main, UserDefaults.lproTabBar.iOS26GlassTabs, let dict = dict else {
            return dict
        }
        let mutable = NSMutableDictionary(dictionary: dict)
        mutable[Self.key] = false
        return mutable
    }
}
