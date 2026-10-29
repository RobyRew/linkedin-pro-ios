import Foundation

// Decides whether a decoded DashFeedUpdate was surfaced into the feed because a
// connection reacted to it, and with which reaction.
//
// LinkedIn carries this only as display text in the update's header
// (DashFeedHeaderComponent.text, a DashTextViewModel) - there is no
// machine-readable reaction type on the header - so detection matches the header
// string against LProReaction.headerPatterns. All reads are KVC and guarded by
// respondsToSelector, so a model whose shape changed is a miss, not a crash. The
// exact key path and the live text format are to be confirmed on-device (Striker
// `obj <update>` / `watch DashFeedUpdateBuilder build:error:`).
enum FeedReason {
    static func surfacingReaction(of update: NSObject) -> LProReaction? {
        guard let text = headerText(of: update)?.lowercased() else { return nil }
        for reaction in LProReaction.allCases
        where reaction.headerPatterns.contains(where: { text.contains($0) }) {
            return reaction
        }
        return nil
    }

    // update.header -> DashFeedHeaderComponent ; .text -> DashTextViewModel ; .text -> String
    private static func headerText(of update: NSObject) -> String? {
        guard let header = value(update, "header") as? NSObject else { return nil }
        let textValue = value(header, "text")
        if let string = textValue as? String { return string }
        guard let model = textValue as? NSObject else { return nil }
        for key in ["text", "accessibilityText", "string"] {
            if let string = value(model, key) as? String { return string }
        }
        return nil
    }

    // KVC read guarded by respondsToSelector (raw value(forKey:) throws on an
    // unknown key).
    private static func value(_ object: NSObject, _ key: String) -> Any? {
        guard object.responds(to: NSSelectorFromString(key)) else { return nil }
        return object.value(forKey: key)
    }
}
