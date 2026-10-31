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
    private static var markKey: UInt8 = 0

    static func apply(_ bar: UINavigationBar) {
        guard #available(iOS 26.0, *) else { return }
        guard UserDefaults.lproTabBar.topBarGlass else { return }
        // Skip if the bar already carries the appearance we installed (so setting it
        // -> layoutSubviews -> here -> identity match -> return: no loop). When
        // LinkedIn swaps in its own appearance, identity differs and we re-apply.
        if let mark = objc_getAssociatedObject(bar, &markKey) as? UINavigationBarAppearance,
           bar.standardAppearance === mark { return }

        let appearance = UINavigationBarAppearance()
        appearance.configureWithDefaultBackground()
        appearance.backgroundColor = nil
        // A translucent material so the bar reads as glass rather than a solid fill;
        // this makes UIKit build the effect view in place of the opaque colour view.
        appearance.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterial)

        bar.standardAppearance = appearance
        bar.compactAppearance = appearance
        bar.scrollEdgeAppearance = appearance
        bar.compactScrollEdgeAppearance = appearance
        bar.isTranslucent = true
        objc_setAssociatedObject(bar, &markKey, appearance, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
}
