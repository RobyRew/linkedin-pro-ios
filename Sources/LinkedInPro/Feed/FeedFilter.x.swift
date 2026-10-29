import Orion
import Foundation

// Phase 2 - feed filter, at the data layer.
//
// DashFeedUpdateBuilder (VoyagerLibs) builds one DashFeedUpdate from the decoded
// Voyager response; build:error: is inherited from RecordTemplateBuilder, so
// hooking it on DashFeedUpdateBuilder scopes the override to feed updates. We
// call orig, classify the update (FeedReason), and return nil to drop it when its
// category is one the user chose to hide - so it never reaches the feed UI.
// Data-layer filtering survives LinkedIn's feed UI/SDUI redesigns.
//
// NEEDS-DEVICE: confirm nil cleanly drops a single update (vs erroring the batch);
// the category heuristics (header text / content class) are tuned from the log.
struct FeedFilterGroup: HookGroup {}

class DashFeedUpdateBuilderHook: ClassHook<NSObject> {
    typealias Group = FeedFilterGroup
    static let targetName = "DashFeedUpdateBuilder"

    func build(_ data: Any?, error: AutoreleasingUnsafeMutablePointer<NSError?>?) -> NSObject? {
        guard let update = orig.build(data, error: error) else { return nil }
        let options = UserDefaults.lproFeedFilter

        switch FeedReason.category(of: update) {
        case .reactionSurfaced(let reaction):
            if options.hideReactionSurfaced && options.reactions.contains(reaction) {
                return drop(update, "reaction:\(reaction.rawValue)")
            }
        case .sponsored:
            if options.hideSponsored { return drop(update, "sponsored") }
        case .promotion:
            if options.hidePromotions { return drop(update, "promotion") }
        case .premiumUpsell:
            if options.hidePremiumUpsell { return drop(update, "premium-upsell") }
        case .organic:
            break
        }
        return update
    }

    private func drop(_ update: NSObject, _ why: String) -> NSObject? {
        LProLog.write("[feed] hid \(why)")
        return nil
    }
}
