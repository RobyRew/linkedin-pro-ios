import Foundation

// Premium settings.
//
// `features` backs the POC panel: one stored flag per entry in
// PremiumFeatureCatalog, all defaulting to ON. The flags are persisted and
// handed to PremiumPOC.sync(), which only logs - nothing in the app reads them
// and no premium behaviour is attached to them.
struct PremiumOptions: Codable, Equatable {
    var spoofPremium: Bool = true
    // Master switch for the feature panel; it is a "set all" control rather
    // than a separate gate.
    var masterEnabled: Bool = true
    // id -> on. A missing id means ON.
    var features: [String: Bool] = [:]

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        spoofPremium = try c.decodeIfPresent(Bool.self, forKey: .spoofPremium) ?? true
        masterEnabled = try c.decodeIfPresent(Bool.self, forKey: .masterEnabled) ?? true
        features = try c.decodeIfPresent([String: Bool].self, forKey: .features) ?? [:]
    }

    func isEnabled(_ id: String) -> Bool { features[id] ?? true }

    mutating func set(_ id: String, _ on: Bool) { features[id] = on }

    mutating func setAll(_ on: Bool) {
        for group in PremiumFeatureCatalog.groups {
            for item in group.items { features[item.id] = on }
        }
        masterEnabled = on
    }

    var allEnabled: Bool {
        PremiumFeatureCatalog.groups.allSatisfy { group in
            group.items.allSatisfy { isEnabled($0.id) }
        }
    }

    var enabledCount: Int {
        PremiumFeatureCatalog.groups.reduce(0) { total, group in
            total + group.items.filter { isEnabled($0.id) }.count
        }
    }

    var featureCount: Int {
        PremiumFeatureCatalog.groups.reduce(0) { $0 + $1.items.count }
    }
}

extension UserDefaults {
    @UserDefault(key: "lproPremium", defaultValue: PremiumOptions())
    static var lproPremium: PremiumOptions
}
