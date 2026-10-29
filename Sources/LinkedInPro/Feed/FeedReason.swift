import Foundation

// What kind of feed item a decoded DashFeedUpdate is, so FeedFilter can drop it
// per the user's toggles. LinkedIn has no single machine-readable flag for most
// of these, so detection reads the header social-proof text plus the content
// component's class name, all via guarded KVC. Heuristic and locale-sensitive;
// confirmed/extended on-device (Striker `obj <update>` / the tweak log).
enum FeedCategory: Equatable {
    case organic
    case reactionSurfaced(LProReaction)
    case commentSurfaced // "X commented on this"
    case repostSurfaced  // "X reposted this"
    case sponsored      // "Promoted" ads
    case promotion      // suggestions / recommendations / follow cards
    case premiumUpsell  // LinkedIn Premium upsell cards
}

enum FeedReason {
    static func category(of update: NSObject) -> FeedCategory {
        let header = (headerText(of: update) ?? "").lowercased()
        let content = (contentClassName(of: update) ?? "").lowercased()

        if content.contains("upsell") || content.contains("premium") || header.contains("premium") {
            return .premiumUpsell
        }
        if header.contains("promoted") || header.contains("sponsored") {
            return .sponsored
        }
        if header.contains("commented on this") || header.contains("commented on a post")
            || header.contains("replied to this") {
            return .commentSurfaced
        }
        if header.contains("reposted this") || header.contains("reposted a post") {
            return .repostSurfaced
        }
        for reaction in LProReaction.allCases
        where reaction.headerPatterns.contains(where: { header.contains($0) }) {
            return .reactionSurfaced(reaction)
        }
        if content.contains("recommend") || content.contains("discover") || content.contains("suggestion")
            || promotionHeaderPatterns.contains(where: { header.contains($0) }) {
            return .promotion
        }
        return .organic
    }

    private static let promotionHeaderPatterns = [
        "suggested", "recommended", "people you may know", "add to your feed",
        "you might", "trending", "pages for you", "groups you",
        "newsletters for you", "jobs for you", "courses for you", "events for you",
        "based on your", "because you follow", "popular on linkedin",
        "top picks for you", "linkedin news", "puzzles", "games you may",
    ]

    // update.header (DashFeedHeaderComponent).text (DashTextViewModel).text
    private static func headerText(of update: NSObject) -> String? {
        guard let header = value(update, "header") as? NSObject else { return nil }
        let textValue = value(header, "text")
        if let s = textValue as? String { return s }
        guard let model = textValue as? NSObject else { return nil }
        for key in ["text", "accessibilityText", "string"] {
            if let s = value(model, key) as? String { return s }
        }
        return nil
    }

    // The class of the update's main content component (e.g. a premium upsell or
    // a recommendation carousel vs an ordinary post component).
    private static func contentClassName(of update: NSObject) -> String? {
        for key in ["content", "contentUnion", "footer", "annotation"] {
            if let component = value(update, key) as? NSObject {
                return NSStringFromClass(type(of: component))
            }
        }
        return nil
    }

    private static func value(_ object: NSObject, _ key: String) -> Any? {
        guard object.responds(to: NSSelectorFromString(key)) else { return nil }
        return object.value(forKey: key)
    }
}
