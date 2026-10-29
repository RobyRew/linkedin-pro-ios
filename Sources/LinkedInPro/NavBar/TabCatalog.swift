import UIKit
import ObjectiveC.runtime

// The tab types LinkedIn's factory can build, minus the center "post" action
// (that is a floating button, not a bar tab). Selector names are the factory's
// own zero-argument methods; tabName is read from the returned LINMainNavTabType
// at runtime so nothing here depends on the display string.
enum TabCatalog {
    struct Extra {
        let selector: String   // selector on MainNavTabTypeFactory
        let title: String      // human label for settings
        let symbol: String     // SF Symbol fallback when no real icon was captured
    }

    static let extras: [Extra] = [
        Extra(selector: "messaging",     title: "Chat / Messaging", symbol: "bubble.left.and.bubble.right.fill"),
        Extra(selector: "jobs",          title: "Jobs",             symbol: "briefcase.fill"),
        Extra(selector: "notifications", title: "Notifications",    symbol: "bell.fill"),
        Extra(selector: "video",         title: "Video",            symbol: "play.rectangle.fill"),
        Extra(selector: "games",         title: "Games",            symbol: "gamecontroller.fill"),
        Extra(selector: "trendsHub",     title: "Trends Hub",       symbol: "chart.line.uptrend.xyaxis"),
        Extra(selector: "more",          title: "More",             symbol: "ellipsis"),
        Extra(selector: "myNetwork",     title: "My Network",       symbol: "person.2.fill"),
        Extra(selector: "feed",          title: "Home / Feed",      symbol: "house.fill"),
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

    // A fresh factory instance. The class is registered lazily by LinkedIn, so
    // this can return nil before the tab bar has been built once.
    static func makeFactory() -> NSObject? {
        guard let cls = NSClassFromString("_TtC14HomeNavAPIImpl21MainNavTabTypeFactory") as? NSObject.Type
        else { return nil }
        return cls.init()
    }

    static func tabType(selector: String, factory: NSObject?) -> NSObject? {
        guard let factory, factory.responds(to: NSSelectorFromString(selector)) else { return nil }
        return factory.perform(NSSelectorFromString(selector))?.takeUnretainedValue() as? NSObject
    }

    private static var resolvedNames: [String: String] = [:]

    // tabName for an extra selector, resolved through the live factory. nil when
    // the factory is not registered yet (call again after the bar exists).
    // Cached once resolved: settings reads this every render.
    static func resolvedName(forSelector selector: String) -> String? {
        if let cached = resolvedNames[selector] { return cached }
        guard let type = tabType(selector: selector, factory: makeFactory()) else { return nil }
        let name = tabName(type)
        resolvedNames[selector] = name
        return name
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
