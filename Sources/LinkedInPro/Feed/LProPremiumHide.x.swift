import Orion
import UIKit

// Hides LinkedIn Premium upsell UI (e.g. the Me-tab "Try Premium for 0" button)
// when "Hide Premium upselling" is on. The upsell buttons aren't in the account
// panel's own view tree, so rather than binding a class we scan live views for a
// label whose text names Premium and hide the enclosing tappable control. Each
// hit is logged, which doubles as RE for where the upsells actually live. Runs on
// viewDidAppear (not per layout) to stay cheap, and does nothing when the option
// is off.
struct PremiumHideGroup: HookGroup {}

class PremiumHideHook: ClassHook<UIViewController> {
    typealias Group = PremiumHideGroup

    func viewDidAppear(_ animated: Bool) {
        orig.viewDidAppear(animated)
        guard UserDefaults.lproFeedFilter.hidePremiumUpsell else { return }
        LProPremium.sweepSoon()
    }
}

enum LProPremium {
    // Upsells are added after a screen appears (server data, banners), so sweep
    // now and twice more once the screen has settled.
    static func sweepSoon() {
        hideUpsells()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { hideUpsells() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { hideUpsells() }
    }

    static func hideUpsells() {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
        for window in windows { walk(window) }
    }

    private static func walk(_ view: UIView) {
        if let hit = text(in: view), isUpsell(hit) {
            let target = enclosingControl(of: view) ?? view
            if !target.isHidden {
                target.isHidden = true
                LProLog.write("[premium] hid \(NSStringFromClass(type(of: target))): \(hit)")
            }
            return
        }
        for sub in view.subviews { walk(sub) }
    }

    // SDUI text is carried as an accessibility label, not UILabel.text (the feed
    // dump shows every text block as ax=...), so both are read.
    private static func text(in view: UIView) -> String? {
        if let label = view as? UILabel, let t = label.text, !t.isEmpty { return t }
        if view.isAccessibilityElement, let a = view.accessibilityLabel, !a.isEmpty { return a }
        return nil
    }

    private static func isUpsell(_ text: String) -> Bool {
        let t = text.lowercased()
        guard t.contains("premium") else { return false }
        let action = ["try", "free", "retry", "redeem", "month", "reactivate", "upgrade",
                      "unlock", "go premium", "on us", "50% off", "off your",
                      "\u{20ac}", "$", "\u{00a3}"]
        return action.contains(where: { t.contains($0) })
    }

    private static func enclosingControl(of view: UIView) -> UIView? {
        var current: UIView? = view
        var hops = 0
        while let v = current, hops < 5 {
            if v is UIControl { return v }
            current = v.superview
            hops += 1
        }
        return nil
    }
}
