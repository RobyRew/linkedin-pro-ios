import Orion
import UIKit
import Foundation
import ObjectiveC.runtime

// Toggleable iOS 26+ liquid-glass TOP navigation bar.
//
// On-device RE showed LinkedIn's bar background is a solid colour view
// (_UIBarBackground._colorAndImageView1, _effectView1 == nil) - the "white" bar -
// and that LinkedIn re-applies its own appearance repeatedly. This forces the bar
// background to a translucent glass MATERIAL instead: an appearance whose
// backgroundEffect is a glass/blur effect (so UIKit builds the effect view, not the
// white colour view). It is re-applied whenever LinkedIn swaps the appearance back
// (identity-guarded so an unchanged bar is a no-op, no layout loop).
//
// Gated on iOS 26+ and the topBarGlass toggle; off => LinkedIn's own bar is left
// untouched. Kept separate from the dormant GlassChrome group.
struct GlassTopBarGroup: HookGroup {}

class GlassTopBarNavHook: ClassHook<UINavigationBar> {
    typealias Group = GlassTopBarGroup

    func didMoveToWindow() {
        orig.didMoveToWindow()
        GlassTopBar.apply(target)
    }

    func layoutSubviews() {
        orig.layoutSubviews()
        GlassTopBar.apply(target)
    }
}

enum GlassTopBar {
    private static let glassTag = 0x4C50_4762   // 'LPGb'

    // Setting the bar's appearance to a glass material rendered visibility=hidden on
    // this build (confirmed on device), so instead insert a glass effect view we own
    // directly ABOVE LinkedIn's background fill (which carries the solid "white"
    // colour) and below its content platter. We control it, so it is reliably visible.
    static func apply(_ bar: UINavigationBar) {
        guard #available(iOS 26.0, *) else { return }
        guard UserDefaults.lproTabBar.topBarGlass else {
            // Toggle off: remove our glass view if present.
            bar.viewWithTag(glassTag)?.removeFromSuperview()
            return
        }

        if let existing = bar.viewWithTag(glassTag) {
            existing.frame = bar.bounds
            keepAboveBarBackground(existing, in: bar)
            return
        }

        // A thin material reads as frosted glass in both themes (UIGlassEffect is not
        // assignable here); the direct effect view is always visible, unlike the
        // appearance route.
        let effectView = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterial))
        effectView.tag = glassTag
        effectView.isUserInteractionEnabled = false
        effectView.frame = bar.bounds
        effectView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        bar.addSubview(effectView)
        keepAboveBarBackground(effectView, in: bar)
    }

    // Place the glass view just above LinkedIn's _UIBarBackground (so it hides the
    // solid fill) but below the nav content, re-ordering if LinkedIn re-stacks.
    private static func keepAboveBarBackground(_ glass: UIView, in bar: UINavigationBar) {
        var index = 1
        for (i, sub) in bar.subviews.enumerated()
        where NSStringFromClass(type(of: sub)).contains("_UIBarBackground") { index = i + 1 }
        let target = min(index, bar.subviews.count - 1)
        if bar.subviews.firstIndex(of: glass) != target {
            bar.insertSubview(glass, at: max(0, target))
        }
    }
}
