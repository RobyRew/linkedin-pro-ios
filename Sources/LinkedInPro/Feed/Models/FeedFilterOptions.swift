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

    var headerPatterns: [String] {
        switch self {
        case .like: return ["likes this", "liked this"]
        case .celebrate: return ["celebrates this", "celebrated this"]
        case .love: return ["loves this", "loved this"]
        case .support: return ["supports this", "supported this"]
        case .insightful: return ["finds this insightful", "found this insightful"]
        case .funny: return ["finds this funny", "found this funny"]
        }
    }
}

struct FeedFilterOptions: Codable, Equatable {
    // Hide posts surfaced only because a connection reacted (by reaction type).
    var hideReactionSurfaced: Bool = false
    var reactions: Set<LProReaction> = Set(LProReaction.allCases)

    // Hide "Promoted"/sponsored posts (ads).
    var hideSponsored: Bool = false
    // Hide LinkedIn's suggestion/recommendation promo cards (not real posts).
    var hidePromotions: Bool = false
    // Hide premium upsell cards in the feed AND the premium upsell buttons in the UI.
    var hidePremiumUpsell: Bool = false
}

extension UserDefaults {
    @UserDefault(key: "lproFeedFilter", defaultValue: FeedFilterOptions())
    static var lproFeedFilter: FeedFilterOptions
}
