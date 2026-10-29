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
    }
}

extension UserDefaults {
    @UserDefault(key: "lproTabBar", defaultValue: TabBarOptions())
    static var lproTabBar: TabBarOptions
}
