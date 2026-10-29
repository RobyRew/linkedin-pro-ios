import Foundation

// Premium spoof options. Defaults ON (the point of the feature).
struct PremiumOptions: Codable, Equatable {
    var spoofPremium: Bool = true

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        spoofPremium = try c.decodeIfPresent(Bool.self, forKey: .spoofPremium) ?? true
    }
}

extension UserDefaults {
    @UserDefault(key: "lproPremium", defaultValue: PremiumOptions())
    static var lproPremium: PremiumOptions
}
