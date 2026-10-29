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
        LProPremium.hideUpsells()
    }
}

enum LProPremium {
    static func hideUpsells() {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
        for window in windows { walk(window) }
    }

    private static func walk(_ view: UIView) {
        if let label = view as? UILabel, isUpsell(label.text) {
            let target = enclosingControl(of: label) ?? label
            if !target.isHidden {
                target.isHidden = true
                LProLog.write("[premium] hid \(NSStringFromClass(type(of: target))): \(label.text ?? "")")
            }
            return
        }
        for sub in view.subviews { walk(sub) }
    }

    private static func isUpsell(_ text: String?) -> Bool {
        guard let t = text?.lowercased(), t.contains("premium") else { return false }
        return t.contains("try") || t.contains("free") || t.contains("retry")
            || t.contains("redeem") || t.contains("month") || t.contains("reactivate")
            || t.contains("\u{20ac}") || t.contains("$") || t.contains("\u{00a3}")
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
