import Orion
import LinkedInProC
import UIKit
import Foundation
import ObjectiveC.runtime

// Entry point. Orion instantiates this after orion_init() (see LinkedInProC/Tweak.m).
// init() runs on the app's main thread at launch, before most of LinkedIn's UI.
struct LinkedInPro: Tweak {
    init() {
        LProLog.boot()
        HookRegistry.shared.logTargetInventory()
        LProDevKit.startIfEnabled()
        if LProDevKit.isEnabled {
            // DevKit-only: log each VC that appears and dump the account panel's
            // view tree to the log when the Me tab opens (async RE over USB).
            HookRegistry.shared.activate(DevKitViewLogGroup(), named: "devkit-viewlog",
                                         requiring: ["UIViewController"])
        }

        // Phase 1 - Settings: a version-independent UINavigationController hook, so
        // the only requirement is UIKit itself.
        HookRegistry.shared.activate(SettingsInjectionGroup(), named: "settings-injection",
                                     requiring: ["UINavigationController"])
        // The real entry: a row above "Settings & Privacy" in the Me-tab account panel.
        HookRegistry.shared.activate(AccountPanelEntryGroup(), named: "account-panel-entry",
                                     requiring: ["UIViewController"])
        // Hide premium upsell UI (the Me-tab "Try Premium" button, etc.) when enabled.
        HookRegistry.shared.activate(PremiumHideGroup(), named: "premium-hide",
                                     requiring: ["UIViewController"])

        // Phase 2 - Feed: hook DashFeedUpdateBuilder.build:error: (VoyagerLibs) to drop
        // posts surfaced by a connection's reaction, filtered by reaction type.
        HookRegistry.shared.activate(FeedFilterGroup(), named: "feed-filter",
                                     requiring: ["DashFeedUpdateBuilder"])

        // Later phases activate here, each guarded by HookRegistry.activate(...):
        //   Phase 3  NavBar  -> NavBarCustomizeGroup (+ GlassOptOut.apply())
    }

    // Orion's default handleError forwards to handleErrorDefault, which calls
    // fatalError on ANY failed hook activation — including default-group hooks
    // that run before init(), so the guards above cannot protect against it.
    // Override it to log and continue: a selector that LinkedIn renamed on a new
    // build must degrade one feature, not kill the whole app (worse on sideload,
    // where users cannot easily grab a crash log).
    static func handleError(_ error: OrionHookError) {
        LProLog.write("[orion] non-fatal hook error: \(error.description)")
        // Deliberately NOT calling handleErrorDefault(error).
    }
}
