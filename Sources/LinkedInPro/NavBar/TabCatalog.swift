import UIKit
import ObjectiveC.runtime

// The tab types LinkedIn's factory can build, minus the center "post" action
// (that is a floating button, not a bar tab). Selector names are the factory's
// own zero-argument methods.
//
// The factory class is Swift and is only ever used through the live instance
// Orion hands MainNavTabsOrderHook. Constructing one ourselves
// (`NSObject.Type.init()`) traps inside LinkedIn, so nothing here instantiates
// it: the settings UI resolves names from UserDefaults only.
enum TabCatalog {
    struct Extra {
        let selector: String   // selector on MainNavTabTypeFactory
        let title: String      // human label for settings
        let symbol: String     // SF Symbol fallback when no real icon was captured
    }

    // The bar's own tab types map live through -tabName:
    //   0 Feed, 1 Jobs, 2 MyNetwork, 3 Notifications, 4 More
    // MainNavTabTypeFactory also exposes a `messaging` factory method; it is not
    // one of the bar's default types, so it is offered as an EXPERIMENTAL extra -
    // TabEngine builds it through LinkedIn's own factory + VC factory and adds it
    // with setViewControllers, which is non-fatal if the build will not bind it.
    static let extras: [Extra] = [
        Extra(selector: "feed",          title: "Home / Feed",   symbol: "house.fill"),
        Extra(selector: "jobs",          title: "Jobs",          symbol: "briefcase.fill"),
        Extra(selector: "myNetwork",     title: "My Network",    symbol: "person.2.fill"),
        Extra(selector: "notifications", title: "Notifications", symbol: "bell.fill"),
        Extra(selector: "messaging",     title: "Messaging / Chats", symbol: "message.fill"),
        Extra(selector: "more",          title: "More",          symbol: "ellipsis"),
    ]

    static func extra(for selector: String) -> Extra? {
        extras.first { $0.selector == selector }
    }

    // Fallback SF Symbol for a tab that was never rendered by LinkedIn.
    static func symbol(forTabNamed name: String) -> String {
        let key = name.lowercased()
        if let match = extras.first(where: {
            $0.title.lowercased().contains(key) || key.contains($0.selector.lowercased())
        }) { return match.symbol }
        if key.contains("network") { return "person.2.fill" }
        if key.contains("feed") || key.contains("home") { return "house.fill" }
        return "square.grid.2x2.fill"
    }

    static func tabName(_ tabType: NSObject) -> String {
        if tabType.responds(to: NSSelectorFromString("tabName")),
           let n = tabType.value(forKey: "tabName") as? String, !n.isEmpty { return n }
        return NSStringFromClass(type(of: tabType))
    }

    // Resolves a tab type from one of LinkedIn's own zero-argument factory methods
    // (never a model we construct - that traps).
    //
    // On this build the tab-type constructors (+feed / +messaging / +jobs / …) are
    // CLASS methods on LINMainNavTabType, not instance methods on the factory, so
    // calling them on the live factory instance returned nil - the reason Messaging
    // / Chats logged "cannot build messaging". Try the factory instance first (older
    // builds), then the class method on LINMainNavTabType.
    static func tabType(selector: String, factory: NSObject?) -> NSObject? {
        let sel = NSSelectorFromString(selector)
        if let factory, factory.responds(to: sel),
           let obj = factory.perform(sel)?.takeUnretainedValue() as? NSObject {
            return obj
        }
        if let cls = NSClassFromString("LINMainNavTabType") {
            let classObj = cls as AnyObject
            if classObj.responds(to: sel),
               let obj = classObj.perform(sel)?.takeUnretainedValue() as? NSObject {
                return obj
            }
        }
        return nil
    }

    // "myNetwork" and "My Network" / "MY_NETWORK" compare equal.
    static func normalized(_ s: String) -> String {
        s.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}

// Real tab icons captured from the bar as LinkedIn builds each item, so the
// settings list shows what the tab actually looks like. Falls back to an SF
// Symbol for extras that have never been rendered.
enum TabIconStore {
    private static var icons: [String: UIImage] = [:]

    static func record(_ image: UIImage?, for name: String) {
        guard let image, !name.isEmpty else { return }
        icons[name] = image
    }

    static func icon(for name: String) -> UIImage? { icons[name] }

    static func image(for name: String) -> UIImage? {
        icons[name] ?? UIImage(systemName: TabCatalog.symbol(forTabNamed: name))
    }
}
