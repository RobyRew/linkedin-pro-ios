import Foundation

// LinkedIn's six feed reactions. rawValue is our stable key; voyagerRaw is the
// VoyagerLibs DashFeedSocialReactionType enum identifier (confirmed in the
// binary strings). displayName/symbol drive the settings UI; headerPatterns are
// the English social-proof phrases LinkedIn shows in a post's header when the
// post was surfaced by that reaction ("X likes this"). Patterns are matched
// case-insensitively and are confirmed/extended per locale on-device.
enum LProReaction: String, CaseIterable, Codable, Hashable {
    case like, celebrate, love, support, insightful, funny

    var voyagerRaw: String {
        switch self {
        case .like: return "LIKE"
        case .celebrate: return "PRAISE"
        case .love: return "APPRECIATION"
        case .support: return "EMPATHY"
        case .insightful: return "INTEREST"
        case .funny: return "ENTERTAINMENT"
        }
    }

    var displayName: String {
        switch self {
        case .like: return "Like"
        case .celebrate: return "Celebrate"
        case .love: return "Love"
        case .support: return "Support"
        case .insightful: return "Insightful"
        case .funny: return "Funny"
        }
    }

    var symbol: String {
        switch self {
        case .like: return "hand.thumbsup"
        case .celebrate: return "hands.clap"
        case .love: return "heart"
        case .support: return "hands.and.sparkles"
        case .insightful: return "lightbulb"
        case .funny: return "face.smiling"
        }
    }

    // Social-proof header text LinkedIn shows when a post is surfaced by this
    // reaction. Includes the plural "... and N others like this" form.
    var headerPatterns: [String] {
        switch self {
        case .like: return ["likes this", "liked this", "like this"]
        case .celebrate: return ["celebrates this", "celebrated this", "celebrate this"]
        case .love: return ["loves this", "loved this", "love this"]
        case .support: return ["supports this", "supported this", "support this"]
        case .insightful: return ["finds this insightful", "found this insightful", "find this insightful"]
        case .funny: return ["finds this funny", "found this funny", "find this funny"]
        }
    }
}

struct FeedFilterOptions: Codable, Equatable {
    // Hide posts surfaced only because a connection reacted (by reaction type).
    // Opt-in (off): it removes real posts the user may want.
    var hideReactionSurfaced: Bool = false
    var reactions: Set<LProReaction> = Set(LProReaction.allCases)

    // The three clean-up options ship ON: they only remove ads / promo / upsell
    // chrome, which is the point of the tweak. A user can turn each off.
    var hideSponsored: Bool = true     // "Promoted" ads
    var hidePromotions: Bool = true    // suggestion / recommendation promo cards
    var hidePremiumUpsell: Bool = true // premium upsell cards + the UI upsell buttons

    // Decode missing keys to their declared defaults, so a blob written by an
    // earlier build (which had no clean-up keys, or had them defaulting off)
    // reads back with the clean-up options ON rather than nil-crashing or
    // silently off. Only an explicitly-stored false turns an option off.
    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = FeedFilterOptions()
        hideReactionSurfaced = try c.decodeIfPresent(Bool.self, forKey: .hideReactionSurfaced) ?? d.hideReactionSurfaced
        reactions = try c.decodeIfPresent(Set<LProReaction>.self, forKey: .reactions) ?? d.reactions
        hideSponsored = try c.decodeIfPresent(Bool.self, forKey: .hideSponsored) ?? d.hideSponsored
        hidePromotions = try c.decodeIfPresent(Bool.self, forKey: .hidePromotions) ?? d.hidePromotions
        hidePremiumUpsell = try c.decodeIfPresent(Bool.self, forKey: .hidePremiumUpsell) ?? d.hidePremiumUpsell
    }
}

extension UserDefaults {
    @UserDefault(key: "lproFeedFilter", defaultValue: FeedFilterOptions())
    static var lproFeedFilter: FeedFilterOptions
}
