import Orion
import Foundation

// Phase 2 - feed filter, at the data layer.
//
// DashFeedUpdateBuilder (VoyagerLibs) builds one DashFeedUpdate from the decoded
// Voyager response; build:error: is inherited from RecordTemplateBuilder, so
// hooking it on DashFeedUpdateBuilder scopes the override to feed updates only.
// We call orig to get the decoded update, and return nil for an update that was
// surfaced by a connection's reaction of a type the user chose to hide - so the
// post never reaches the feed UI. Data-layer filtering survives LinkedIn's feed
// UI/SDUI redesigns.
//
// NEEDS-DEVICE: confirm that returning nil cleanly drops the single update
// (rather than erroring the batch). If not, the fallback is to filter at the
// feed collection/response builder; the detection in FeedReason is unchanged.

struct FeedFilterGroup: HookGroup {}

class DashFeedUpdateBuilderHook: ClassHook<NSObject> {
    typealias Group = FeedFilterGroup
    static let targetName = "DashFeedUpdateBuilder"

    func build(_ data: Any?, error: AutoreleasingUnsafeMutablePointer<NSError?>?) -> NSObject? {
        guard let update = orig.build(data, error: error) else { return nil }
        let options = UserDefaults.lproFeedFilter
        guard options.hideReactionSurfaced else { return update }
        if let reaction = FeedReason.surfacingReaction(of: update), options.reactions.contains(reaction) {
            LProLog.write("[feed] hid \(reaction.rawValue)-surfaced update")
            return nil
        }
        return update
    }
}
