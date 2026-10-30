import UIKit
import Foundation

// One coalesced, bounded pass over the foreground window that hides sponsored /
// promoted chrome and premium upsell controls by their visible text or
// accessibility label.
//
// Why a text sweep at all: the markers are accessibility labels or short UILabels,
// not a single hookable class, so matching on text is the version-independent
// primitive - it survives LinkedIn renaming its view classes. The SDUI main feed
// is filtered at its data source (SDUIFeedFilter); this sweep catches sponsored
// and upsell chrome elsewhere (search, jobs, notifications, the Me panel).
//
// The earlier approach walked EVERY window of EVERY scene three times on EVERY
// UIViewController.viewDidAppear - dozens of full-tree walks per screen. This
// replaces that with:
//   - coalescing: many triggers in one run loop collapse to a single sweep;
//   - scope: only the foreground key window, not keyboard / alert / overlay windows;
//   - bounds: a node budget, and skipping hidden or transparent subtrees;
//   - one pass that applies every enabled rule, not a separate walk per rule.
enum LProViewSweeper {
    private static var pending = false

    // Upper bound on views visited per sweep. A LinkedIn screen's live tree is a
    // few thousand nodes; this caps a pathological tree without truncating a real
    // one. Reaching it logs, so a silent cap never reads as "swept everything".
    private static let nodeBudget = 8000

    private enum Kind: String { case ad, upsell }

    // What this sweep hides, resolved once per pass.
    private struct Rules {
        let ad: Bool      // sponsored / promoted chrome
        let upsell: Bool  // premium upsell controls
        var any: Bool { ad || upsell }
    }

    // Upsell hiding has two independent switches: the Ads panel's "Hide Premium
    // upselling" and the Premium panel's "Hide upgrade prompts". Either one on
    // hides upsells, and neither view overwrites the other.
    private static func currentRules() -> Rules {
        let feed = UserDefaults.lproFeedFilter
        let premium = UserDefaults.lproPremium
        let upsell = feed.hidePremiumUpsell || (premium.spoofPremium && premium.isEnabled("upsells"))
        return Rules(ad: feed.hideSponsored || feed.hidePromotions, upsell: upsell)
    }

    // Coalesce: schedule a single sweep (plus one settle re-check for cards that
    // arrive after the screen appears) no matter how many callers ask inside the
    // debounce window. Early-out entirely when nothing is enabled.
    static func schedule() {
        guard currentRules().any else { return }
        guard !pending else { return }
        pending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            pending = false
            sweep()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { sweep() }
    }

    static func sweep() {
        let rules = currentRules()
        guard rules.any, let window = activeKeyWindow() else { return }
        var budget = nodeBudget
        walk(window, rules: rules, budget: &budget)
        if budget <= 0 {
            LProLog.write("[sweep] node budget (\(nodeBudget)) reached; tree not fully scanned")
        }
    }

    // The window that actually shows LinkedIn's UI: the key window of a
    // foreground-active scene. Falls back to any visible window so a sweep still
    // runs if scene activation state is briefly unset.
    private static func activeKeyWindow() -> UIWindow? {
        let allScenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let active = allScenes.filter { $0.activationState == .foregroundActive }
        let windows = (active.isEmpty ? allScenes : active).flatMap { $0.windows }
        return windows.first(where: { $0.isKeyWindow })
            ?? windows.first(where: { !$0.isHidden })
    }

    private static func walk(_ view: UIView, rules: Rules, budget: inout Int) {
        guard budget > 0 else { return }
        budget -= 1
        // A hidden or transparent subtree is not showing an ad; skip it (this also
        // skips containers a prior sweep already hid).
        if view.isHidden || view.alpha < 0.01 { return }

        if let hit = text(in: view), let kind = classify(hit, rules: rules) {
            let target = enclosingContainer(of: view, for: kind) ?? view
            if !target.isHidden {
                target.isHidden = true
                LProLog.write("[sweep] hid \(kind.rawValue) \(NSStringFromClass(type(of: target))): \(hit.prefix(40))")
            }
            return   // the whole container is gone; nothing below it needs visiting
        }
        for sub in view.subviews { walk(sub, rules: rules, budget: &budget) }
    }

    private static func text(in view: UIView) -> String? {
        if let label = view as? UILabel, let t = label.text, !t.isEmpty { return t }
        if view.isAccessibilityElement, let a = view.accessibilityLabel, !a.isEmpty { return a }
        return nil
    }

    private static func classify(_ text: String, rules: Rules) -> Kind? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !t.isEmpty else { return nil }
        // Short labels only for ads: a post that merely mentions sponsorship is
        // not itself an ad.
        if rules.ad, t.count < 40, isAdMarker(t) { return .ad }
        if rules.upsell, isUpsell(t) { return .upsell }
        return nil
    }

    private static func isAdMarker(_ t: String) -> Bool {
        return t == "promoted" || t == "sponsored"
            || t.hasPrefix("promoted by") || t.hasPrefix("promoted ")
            || t.hasPrefix("sponsored ") || t.contains("sponsored content")
    }

    private static func isUpsell(_ t: String) -> Bool {
        guard t.contains("premium") else { return false }
        let action = ["try", "free", "retry", "redeem", "month", "reactivate", "upgrade",
                      "unlock", "go premium", "on us", "50% off", "off your",
                      "\u{20ac}", "$", "\u{00a3}"]
        return action.contains(where: { t.contains($0) })
    }

    // An ad fills a whole cell/card, so hide the enclosing cell/card/control. An
    // upsell is usually a single tappable control, so hide the nearest UIControl.
    private static func enclosingContainer(of view: UIView, for kind: Kind) -> UIView? {
        var current: UIView? = (kind == .ad) ? view.superview : view
        var hops = 0
        let maxHops = (kind == .ad) ? 10 : 5
        while let v = current, hops < maxHops {
            let name = NSStringFromClass(type(of: v))
            if kind == .ad, name.contains("Cell") || name.contains("Card") { return v }
            if v is UIControl { return v }
            current = v.superview
            hops += 1
        }
        return nil
    }
}
