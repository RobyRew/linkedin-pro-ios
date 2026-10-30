import Orion
import UIKit

// Premium upsell sweep trigger. The upsell hiding itself is the shared
// LProViewSweeper's upsell rule (gated by hidePremiumUpsell, which the Premium
// panel's "Hide upgrade prompts" flag drives via PremiumEnabler). This just
// coalesces a sweep when a screen appears; it is a separate HookGroup so the
// activation and gating in Tweak.init stay unchanged.
struct PremiumHideGroup: HookGroup {}

class PremiumHideHook: ClassHook<UIViewController> {
    typealias Group = PremiumHideGroup

    func viewDidAppear(_ animated: Bool) {
        orig.viewDidAppear(animated)
        LProViewSweeper.schedule()
    }
}

// Skips LinkedIn's premium-feature-access interstitial: the full-screen upsell
// that appears when a non-subscriber taps a premium entry point. Its class name
// contains "PremiumFeatureAccessInterstitial" (RE: PREMIUM-SURFACE.md section 6);
// when "Skip feature interstitials" is on we dismiss it before it is seen. This
// is purely client-side - it removes an upsell gate, it does not grant any data.
struct PremiumInterstitialSkipGroup: HookGroup {}

class PremiumInterstitialSkipHook: ClassHook<UIViewController> {
    typealias Group = PremiumInterstitialSkipGroup

    func viewWillAppear(_ animated: Bool) {
        orig.viewWillAppear(animated)
        guard LProPremiumState.on,
              UserDefaults.lproPremium.isEnabled("interstitials") else { return }
        let name = NSStringFromClass(type(of: target))
        guard name.contains("PremiumFeatureAccessInterstitial") else { return }
        LProLog.write("[premium] skipping interstitial \(name)")
        target.dismiss(animated: false)
    }
}
