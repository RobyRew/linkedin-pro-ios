import Orion
import UIKit
import Foundation
import ObjectiveC.runtime

// iOS 26 Liquid Glass chrome.
//
// Flipping UIDesignRequiresCompatibility (GlassTabs) lets the SYSTEM render the
// floating glass tab bar, but LinkedIn still installs OPAQUE bar appearances per
// screen: a solid top navigation bar, and a solid strip behind the bottom bar on
// tabs other than the feed. This group re-asserts a glass / transparent appearance
// on every UINavigationBar and UITabBar so the whole app reads as one Liquid Glass
// surface - top bar included, on all tabs - and content runs edge to edge under
// the bars (the top bar is clear at rest, glass once content scrolls under it).
//
// Gated by the same LProGlassFlag.isOn as the tab-bar flip; when glass is off this
// leaves LinkedIn's own bars untouched. A runtime toggle-off takes full effect on
// the next launch (already-styled bars keep the glass look until then).
struct GlassChromeGroup: HookGroup {}

class GlassNavBarHook: ClassHook<UINavigationBar> {
    typealias Group = GlassChromeGroup

    func didMoveToWindow() {
        orig.didMoveToWindow()
        GlassChrome.styleNavBar(target)
    }

    func layoutSubviews() {
        orig.layoutSubviews()
        GlassChrome.styleNavBar(target)
    }
}

class GlassTabBarHook: ClassHook<UITabBar> {
    typealias Group = GlassChromeGroup

    func didMoveToWindow() {
        orig.didMoveToWindow()
        GlassChrome.styleTabBar(target)
    }

    func layoutSubviews() {
        orig.layoutSubviews()
        GlassChrome.styleTabBar(target)
    }
}

enum GlassChrome {
    private static var navKey: UInt8 = 0
    private static var tabKey: UInt8 = 0

    // Re-apply only when LinkedIn swapped the appearance out from under us: the
    // appearance object we installed is stored on the bar and compared by identity.
    // Once the bar carries our appearance this is a no-op (so setting the appearance
    // -> layoutSubviews -> here -> identity matches -> return: no layout loop); when
    // LinkedIn replaces it, the identity differs and we re-install once.
    static func styleNavBar(_ bar: UINavigationBar) {
        guard LProGlassFlag.isOn else { return }
        if let marker = objc_getAssociatedObject(bar, &navKey) as? UINavigationBarAppearance,
           bar.standardAppearance === marker { return }

        // Default background renders the Liquid Glass bar on iOS 26 (a system blur
        // below it); the transparent scroll-edge lets content reach the very top
        // edge at rest, with the glass appearing as content scrolls under the bar.
        let standard = UINavigationBarAppearance()
        standard.configureWithDefaultBackground()
        let scrollEdge = UINavigationBarAppearance()
        scrollEdge.configureWithTransparentBackground()

        bar.standardAppearance = standard
        bar.compactAppearance = standard
        bar.scrollEdgeAppearance = scrollEdge
        bar.compactScrollEdgeAppearance = scrollEdge
        bar.isTranslucent = true
        objc_setAssociatedObject(bar, &navKey, standard, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }

    static func styleTabBar(_ bar: UITabBar) {
        guard LProGlassFlag.isOn else { return }
        if let marker = objc_getAssociatedObject(bar, &tabKey) as? UITabBarAppearance,
           bar.standardAppearance === marker { return }

        // Default background => the system floating Liquid Glass island on iOS 26,
        // which replaces the opaque full-width strip LinkedIn puts behind the bar on
        // the non-feed tabs ("background on the bottom sides").
        let appearance = UITabBarAppearance()
        appearance.configureWithDefaultBackground()

        bar.standardAppearance = appearance
        bar.scrollEdgeAppearance = appearance
        bar.isTranslucent = true
        objc_setAssociatedObject(bar, &tabKey, appearance, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
}
