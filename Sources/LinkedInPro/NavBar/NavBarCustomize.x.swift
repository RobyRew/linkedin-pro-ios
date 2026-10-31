import Orion
import UIKit
import Foundation
import ObjectiveC.runtime

// Phase 3, nav bar. LINMainNavViewController is a UITabBarController, and every
// tab type is built by MainNavTabTypeFactory (feed, messaging, myNetwork, jobs,
// notifications, video, games, trendsHub, more). The bar set is server-driven,
// so it already tolerates a varying number of tabs; the hook below rewrites the
// ordered list to the user's set:
//   - icon-only tabs: blank each item's title (LINTabBarItemFactory).
//   - reorder: user permutation of the ordered tab list.
//   - hide: tab types removed from the list.
//   - add: tab types the factory can build but the server did not surface
//     (messaging/chat, video, games, trendsHub, ...), appended, then ordered.
// A change takes effect on relaunch: the order is cached (invalidateTabsOrderCache).
//
// iOS 26 floating-glass tabs: LinkedIn opts out of the iOS 26 design system via
// Info.plist UIDesignRequiresCompatibility=1; flipping that to false for the main
// bundle lets the system render the Liquid Glass "island" tab bar. App-wide and
// experimental, behind a default-off toggle, installed early (before UIKit reads
// the key). See GlassTabsGroup.
struct NavBarCustomizeGroup: HookGroup {}

// Icon-only tabs: blank the returned item's title + nudge the icon to centre.
// Also captures the real item image per tab so the settings list can show the
// same icon the bar uses.
class TabBarItemFactoryHook: ClassHook<NSObject> {
    typealias Group = NavBarCustomizeGroup
    static let targetName = "LINTabBarItemFactory"

    func makeTabBarItemForTabType(_ tabType: Any?) -> UITabBarItem? {
        let item = orig.makeTabBarItemForTabType(tabType)
        if let type = tabType as? NSObject, let item = item {
            TabIconStore.record(item.image, for: TabCatalog.tabName(type))
        }
        guard UserDefaults.lproTabBar.hideLabels, let item = item else { return item }
        item.title = ""
        item.imageInsets = UIEdgeInsets(top: 6, left: 0, bottom: -6, right: 0)
        return item
    }
}

// Rewrites the ordered tab-type list. `target` is the factory instance, so extra
// tab types are resolved through LinkedIn's own zero-argument factory methods
// instead of constructing them ourselves.
class MainNavTabsOrderHook: ClassHook<NSObject> {
    typealias Group = NavBarCustomizeGroup
    static let targetName = "_TtC14HomeNavAPIImpl21MainNavTabTypeFactory"

    func mainNavTabsOrder() -> NSArray {
        let original = orig.mainNavTabsOrder()
        TabEngine.typeFactory = target
        return TabReorder.apply(original, factory: target)
    }
}

enum TabReorder {
    static func apply(_ original: NSArray, factory: NSObject?) -> NSArray {
        let items = original.compactMap { $0 as? NSObject }
        guard !items.isEmpty else { return original }

        var opt = UserDefaults.lproTabBar
        var named = items.map { (name: TabCatalog.tabName($0), obj: $0) }

        // Extras first, so they join the discovered list and can be ordered and
        // icon-cached like any other tab. Resolved through LinkedIn's own live
        // factory instance (never one we create - that traps).
        var extraNames = opt.extraTabNames
        for selector in opt.extraTabs {
            guard let extra = TabCatalog.tabType(selector: selector, factory: factory) else { continue }
            let name = TabCatalog.extraName(selector: selector, tabType: extra)
            extraNames[selector] = name
            if !named.contains(where: { $0.name == name }) {
                named.append((name: name, obj: extra))
                LProLog.write("[navbar] added tab \(name) from \(selector)")
            }
        }

        let names = named.map { $0.name }
        if opt.discoveredTabs != names || opt.extraTabNames != extraNames {
            opt.discoveredTabs = names
            opt.extraTabNames = extraNames
            UserDefaults.lproTabBar = opt
            LProLog.write("[navbar] tabs discovered: \(names)")
        }

        var ordered: [(name: String, obj: NSObject)] = []
        for name in opt.order {
            if let hit = named.first(where: { $0.name == name }) { ordered.append(hit) }
        }
        for entry in named where !ordered.contains(where: { $0.name == entry.name }) {
            ordered.append(entry)
        }

        // Hide last: a hidden tab keeps its place in `order` so unhiding restores
        // its position.
        let visible = ordered.filter { !opt.hiddenTabs.contains($0.name) }
        guard !visible.isEmpty else {
            LProLog.write("[navbar] refusing to hide every tab; keeping the natural set")
            return original
        }
        return visible.map { $0.obj } as NSArray
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

    // Both accessors are called from inside dyld image loading, where UIKit reads
    // UIDesignRequiresCompatibility to configure the design system - so the flip
    // has to happen HERE to take effect. The preference is read from a marker file
    // (LProGlassFlag), a bare stat() that is safe this early; reading UserDefaults
    // here instead re-enters its own initialisation and aborts the launch.
    func object(forInfoDictionaryKey key: String) -> Any? {
        if key == Self.key, target === Bundle.main, LProGlassFlag.isOn {
            return false
        }
        return orig.object(forInfoDictionaryKey: key)
    }

    func infoDictionary() -> NSDictionary? {
        let dict = orig.infoDictionary()
        guard target === Bundle.main, LProGlassFlag.isOn, let dict = dict else {
            return dict
        }
        let mutable = NSMutableDictionary(dictionary: dict)
        mutable[Self.key] = false
        return mutable
    }
}
