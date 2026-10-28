import Foundation
import ObjectiveC.runtime
import Orion

// LinkedIn-specific hook registry. The generic, version-independent activation
// logic (class/selector presence guards) lives in tweak-kit's HookActivator;
// this layer holds the LinkedIn target inventory and routes logging through
// LProLog. No offsets, no hardcoded version checks.
final class HookRegistry {
    static let shared = HookRegistry()
    private init() {}

    // The ObjC classes each subsystem hooks, as discovered by reverse-engineering
    // LinkedIn 2026.1021.1050. Logged at boot so drift on a new build is visible
    // at a glance (and drives re-targeting via tweak-kit's objcinventory diff).
    static let knownTargets: [String: [String]] = [
        "settings": [
            "SettingsViewControllerFactory",
            "LIDevSettingsViewController",
        ],
        "navbar": [
            "LINRootViewControllerManager",
            "LINMainNavTabType",
            "LINTabBarItemFactory",
            "LINMainNavTabBarViewControllerFactory",
            "LINTabViewController",
        ],
        "feed": [
            "DashFeedUpdateBuilder",
            "DashSocialSocialDetail",
            "DashFeedSocialActivityCounts",
            "DashFeedSocialReactionTypeCount",
            "LIDataManager",
        ],
    ]

    // Activates `group` iff every required class (and optional selector) resolves
    // in the running build. Delegates to the shared activator.
    @discardableResult
    func activate(_ group: HookGroup, named name: String,
                  requiring classes: [String],
                  selectors: [(className: String, selector: Selector)] = []) -> Bool {
        HookActivator.activate(group, named: name, requiring: classes,
                               selectors: selectors, log: { LProLog.write("[registry] \($0)") })
    }

    func firstClass(suffix: String) -> AnyClass? { HookActivator.firstClass(suffix: suffix) }

    // Logs how many of each subsystem's known classes resolved on this build.
    func logTargetInventory() {
        for (subsystem, classes) in Self.knownTargets.sorted(by: { $0.key < $1.key }) {
            let missing = classes.filter { NSClassFromString($0) == nil }
            let found = classes.count - missing.count
            let suffix = missing.isEmpty ? "" : " missing=\(missing)"
            LProLog.write("[inventory] \(subsystem): \(found)/\(classes.count)\(suffix)")
        }
    }
}
