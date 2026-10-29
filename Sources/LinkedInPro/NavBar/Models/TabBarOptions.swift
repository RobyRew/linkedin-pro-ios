import Foundation

// Phase 3 (nav bar) options.
struct TabBarOptions: Codable, Equatable {
    // Icon-only tab bar (drop the tab titles).
    var hideLabels: Bool = false
    // Opt LinkedIn back INTO the iOS 26 design system so the bottom bar renders
    // as the floating Liquid Glass "island". App-wide design change, experimental.
    var iOS26GlassTabs: Bool = false
    // User tab order, by tabName; empty = LinkedIn's natural order. Names not
    // listed keep their natural relative order after the listed ones.
    var order: [String] = []
    // The natural tab order the reorder hook last saw (including any extras the
    // user added), by tabName. Populated at runtime so the settings UI can list
    // the real tabs.
    var discoveredTabs: [String] = []
    // tabNames removed from the bar (MainNavTabTypeFactory.mainNavTabsOrder).
    var hiddenTabs: Set<String> = []
    // Extra tabs to add to the bar, keyed by their MainNavTabTypeFactory selector
    // (e.g. "messaging", "video", "games"). LinkedIn ships factories for these
    // but only surfaces some of them by default.
    var extraTabs: [String] = []
    // The tabName each added extra resolved to, written by the tab hook
    // (selector -> tabName) so the settings list can show its real name without
    // touching LinkedIn's factory classes itself.
    var extraTabNames: [String: String] = [:]
    // tabName selected when the app opens; empty = whatever LinkedIn restores.
    var defaultTab: String = ""
    // Long press on the first bar item opens the tweak settings.
    var longPressEntry: Bool = true
    // Force the bottom bar alone into dark appearance.
    var darkTabBar: Bool = false

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = TabBarOptions()
        hideLabels = try c.decodeIfPresent(Bool.self, forKey: .hideLabels) ?? d.hideLabels
        iOS26GlassTabs = try c.decodeIfPresent(Bool.self, forKey: .iOS26GlassTabs) ?? d.iOS26GlassTabs
        order = try c.decodeIfPresent([String].self, forKey: .order) ?? d.order
        discoveredTabs = try c.decodeIfPresent([String].self, forKey: .discoveredTabs) ?? d.discoveredTabs
        hiddenTabs = try c.decodeIfPresent(Set<String>.self, forKey: .hiddenTabs) ?? d.hiddenTabs
        extraTabs = try c.decodeIfPresent([String].self, forKey: .extraTabs) ?? d.extraTabs
        extraTabNames = try c.decodeIfPresent([String: String].self, forKey: .extraTabNames) ?? d.extraTabNames
        defaultTab = try c.decodeIfPresent(String.self, forKey: .defaultTab) ?? d.defaultTab
        longPressEntry = try c.decodeIfPresent(Bool.self, forKey: .longPressEntry) ?? d.longPressEntry
        darkTabBar = try c.decodeIfPresent(Bool.self, forKey: .darkTabBar) ?? d.darkTabBar
    }
}

extension UserDefaults {
    @UserDefault(key: "lproTabBar", defaultValue: TabBarOptions())
    static var lproTabBar: TabBarOptions
}
