import Orion
import UIKit
import Foundation

// App-wide ad / promotion sweep, separate from the feed filter (which catches
// SDUI feed cards). Everything LinkedIn labels as sponsored or promoted is
// hidden on every screen: the marker is an accessibility label ("Promoted",
// "View Sponsored Content") or a short UILabel, and the nearest enclosing cell,
// card or control is hidden - hiding just the label would leave an empty shell.
struct AdsHideGroup: HookGroup {}

class AdsHideHook: ClassHook<UIViewController> {
    typealias Group = AdsHideGroup

    func viewDidAppear(_ animated: Bool) {
        orig.viewDidAppear(animated)
        let opt = UserDefaults.lproFeedFilter
        guard opt.hideSponsored || opt.hidePromotions else { return }
        LProAds.sweepSoon()
    }
}

enum LProAds {
    // Cards are added after the screen appears, so sweep again once it settles.
    static func sweepSoon() {
        hideNow()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { hideNow() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { hideNow() }
    }

    static func hideNow() {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
        for window in windows { walk(window) }
    }

    private static func walk(_ view: UIView) {
        if let hit = text(in: view), isAdMarker(hit) {
            let target = enclosingCard(of: view) ?? view
            if !target.isHidden {
                target.isHidden = true
                LProLog.write("[ads] hid \(NSStringFromClass(type(of: target))): \(hit)")
            }
            return
        }
        for sub in view.subviews { walk(sub) }
    }

    private static func text(in view: UIView) -> String? {
        if let label = view as? UILabel, let t = label.text, !t.isEmpty { return t }
        if view.isAccessibilityElement, let a = view.accessibilityLabel, !a.isEmpty { return a }
        return nil
    }

    // Short labels only: a post that mentions sponsorship is not an ad.
    private static func isAdMarker(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !t.isEmpty, t.count < 40 else { return false }
        return t == "promoted" || t == "sponsored"
            || t.hasPrefix("promoted by") || t.hasPrefix("promoted ")
            || t.hasPrefix("sponsored ") || t.contains("sponsored content")
    }

    private static func enclosingCard(of view: UIView) -> UIView? {
        var current: UIView? = view.superview
        var hops = 0
        while let v = current, hops < 10 {
            let name = NSStringFromClass(type(of: v))
            if name.contains("Cell") || name.contains("Card") { return v }
            if v is UIControl { return v }
            current = v.superview
            hops += 1
        }
        return nil
    }
}
