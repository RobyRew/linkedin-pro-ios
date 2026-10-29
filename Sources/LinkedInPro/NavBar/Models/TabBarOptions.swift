import Foundation

// Phase 3 (nav bar) options. Starts with label hiding; reorder / hide-tab /
// launch-tab land here as their hooks are confirmed on device.
struct TabBarOptions: Codable, Equatable {
    // Icon-only tab bar (drop the tab titles).
    var hideLabels: Bool = false

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        hideLabels = try c.decodeIfPresent(Bool.self, forKey: .hideLabels) ?? false
    }
}

extension UserDefaults {
    @UserDefault(key: "lproTabBar", defaultValue: TabBarOptions())
    static var lproTabBar: TabBarOptions
}
