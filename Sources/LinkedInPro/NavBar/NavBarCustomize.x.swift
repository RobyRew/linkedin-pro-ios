import Orion
import UIKit
import Foundation

// Phase 3, nav bar - first, low-risk customization: icon-only tabs.
//
// LinkedIn builds each bottom-bar item through LINTabBarItemFactory
// (-makeTabBarItemForTabType:, confirmed in the inventory). We call orig and,
// when "Hide tab labels" is on, blank the returned item's title and nudge the
// icon down so it centres. Worst case on a build that changed the factory is a
// no-op (the item is returned untouched) - it cannot break navigation. Reorder /
// hide-tab / launch-tab build on LINRootViewControllerManager
// (-selectMainNavTab:triggeredByUserInteraction:completion:,
// -getViewControllerForTab:) and land once confirmed live.
struct NavBarCustomizeGroup: HookGroup {}

class TabBarItemFactoryHook: ClassHook<NSObject> {
    typealias Group = NavBarCustomizeGroup
    static let targetName = "LINTabBarItemFactory"

    func makeTabBarItemForTabType(_ tabType: Any?) -> UITabBarItem? {
        let item = orig.makeTabBarItemForTabType(tabType)
        guard UserDefaults.lproTabBar.hideLabels, let item = item else { return item }
        item.title = ""
        item.imageInsets = UIEdgeInsets(top: 6, left: 0, bottom: -6, right: 0)
        return item
    }
}
