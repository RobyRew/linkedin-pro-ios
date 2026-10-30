import Orion
import UIKit

// App-wide sponsored / promoted sweep trigger. The hiding itself (and premium
// upsell hiding) is done by the shared LProViewSweeper in one coalesced, bounded
// pass over the foreground window - see that file for why a text / accessibility
// sweep is the version-independent primitive and how the pass is bounded.
struct AdsHideGroup: HookGroup {}

class AdsHideHook: ClassHook<UIViewController> {
    typealias Group = AdsHideGroup

    func viewDidAppear(_ animated: Bool) {
        orig.viewDidAppear(animated)
        LProViewSweeper.schedule()
    }
}
