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

        // Phase 1 - Settings: a version-independent UINavigationController hook, so
        // the only requirement is UIKit itself.
        HookRegistry.shared.activate(SettingsInjectionGroup(), named: "settings-injection",
                                     requiring: ["UINavigationController"])

        // Later phases activate here, each guarded by HookRegistry.activate(...) so
        // a missing class on a new LinkedIn build is a logged skip, never a crash:
        //   Phase 2  Feed    -> FeedFilterGroup (DashFeedUpdateBuilder build:error:)
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
