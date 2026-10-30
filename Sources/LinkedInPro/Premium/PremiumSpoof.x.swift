import Orion
import Foundation

// Premium spoof - the EeveeSpotify-equivalent: flip the client's "am I Premium"
// state so premium-gated UI unlocks. Found by RE (confirmed class + selector +
// return-type encoding in the inventory/binary):
//
//   central gate   LINAuthConfigurationManager -isPremiumSubscriber   -> BOOL
//   per-feature    PremiumFeatureAccess -canViewWVMP / -canBrowseProfiles /
//                  -canViewJobAnalytics / -canViewCompanyInsights /
//                  -canAccessLearningVideos                           -> NSNumber
//   dash twins     DashFeatureAccess -hasAccess, DashProfile -premium /
//                  -showPremiumSubscriberBadge, Me -premiumSubscriber -> NSNumber
//   UI leaf gates  LINFeedHeaderPresenterStyle -shouldDisplayPremiumBar /
//                  -shouldDisplayPremiumLogoV2, LINEntityCardData -isPremium,
//                  LINLEIADashboardConfig -isPremium                  -> BOOL
//
// Return TYPE matters: the `is…/can…`-named primitive gates return BOOL; the
// RecordTemplate property accessors (canView*, premium, hasAccess, …) return a
// BOXED NSNumber - hooking those as BOOL would corrupt the return and crash, so
// each hook below mirrors the real selector's encoding exactly.
//
// Honest scope: this unlocks CLIENT-gated surfaces (the gold badge, premium bars
// and logos, suppressed upsell interstitials, the premium feature ENTRY POINTS).
// The server still enforces the actual data - who-viewed-me lists, analytics,
// InMail credits/send, Learning streams return empty/denied for a non-entitled
// member. So: premium UI, teaser/empty data. Some Swift-dispatched checks can't
// be caught by a selector hook and may stay locked.
struct PremiumSpoofGroup: HookGroup {}

enum LProPremiumState {
    static var on: Bool { UserDefaults.lproPremium.spoofPremium }
    static let yes = NSNumber(value: true)

    // A specific surface is spoofed when the master spoof is on AND that surface's
    // flag is enabled (a missing flag defaults on). This lets the per-feature
    // toggles in the Premium panel actually gate individual surfaces, while the
    // master switch still governs everything.
    static func flag(_ id: String) -> Bool { on && UserDefaults.lproPremium.isEnabled(id) }
}

// MARK: - central gate (BOOL)

class AuthConfigPremiumHook: ClassHook<NSObject> {
    typealias Group = PremiumSpoofGroup
    static let targetName = "LINAuthConfigurationManager"
    func isPremiumSubscriber() -> Bool {
        LProPremiumState.on ? true : orig.isPremiumSubscriber()
    }
}

// MARK: - per-feature access (NSNumber-backed RecordTemplate props)

class PremiumFeatureAccessHook: ClassHook<NSObject> {
    typealias Group = PremiumSpoofGroup
    static let targetName = "PremiumFeatureAccess"
    // Each per-feature gate is mapped to its catalog flag so a specific entry
    // point can be left locked. The data behind each still comes from the server.
    func canViewWVMP() -> NSNumber? { LProPremiumState.flag("wvmp") ? LProPremiumState.yes : orig.canViewWVMP() }
    func canBrowseProfiles() -> NSNumber? { LProPremiumState.flag("wvmp") ? LProPremiumState.yes : orig.canBrowseProfiles() }
    func canViewJobAnalytics() -> NSNumber? { LProPremiumState.flag("job_analytics") ? LProPremiumState.yes : orig.canViewJobAnalytics() }
    func canViewCompanyInsights() -> NSNumber? { LProPremiumState.flag("company_insights") ? LProPremiumState.yes : orig.canViewCompanyInsights() }
    func canAccessLearningVideos() -> NSNumber? { LProPremiumState.flag("learning_videos") ? LProPremiumState.yes : orig.canAccessLearningVideos() }
}

class DashFeatureAccessHook: ClassHook<NSObject> {
    typealias Group = PremiumSpoofGroup
    static let targetName = "DashFeatureAccess"
    func hasAccess() -> NSNumber? { LProPremiumState.on ? LProPremiumState.yes : orig.hasAccess() }
}

// MARK: - profile / me state (NSNumber-backed)

class DashProfilePremiumHook: ClassHook<NSObject> {
    typealias Group = PremiumSpoofGroup
    static let targetName = "DashProfile"
    func premium() -> NSNumber? { LProPremiumState.flag("subscriber_flag") ? LProPremiumState.yes : orig.premium() }
    func showPremiumSubscriberBadge() -> NSNumber? {
        LProPremiumState.flag("badge") ? LProPremiumState.yes : orig.showPremiumSubscriberBadge()
    }
}

class MePremiumHook: ClassHook<NSObject> {
    typealias Group = PremiumSpoofGroup
    static let targetName = "Me"
    func premiumSubscriber() -> NSNumber? { LProPremiumState.flag("subscriber_flag") ? LProPremiumState.yes : orig.premiumSubscriber() }
}

// MARK: - UI leaf gates (BOOL)

class FeedHeaderPremiumHook: ClassHook<NSObject> {
    typealias Group = PremiumSpoofGroup
    static let targetName = "LINFeedHeaderPresenterStyle"
    func shouldDisplayPremiumBar() -> Bool { LProPremiumState.flag("bar") ? true : orig.shouldDisplayPremiumBar() }
    func shouldDisplayPremiumLogoV2() -> Bool { LProPremiumState.flag("logo") ? true : orig.shouldDisplayPremiumLogoV2() }
}

class EntityCardPremiumHook: ClassHook<NSObject> {
    typealias Group = PremiumSpoofGroup
    static let targetName = "LINEntityCardData"
    func isPremium() -> Bool { LProPremiumState.flag("badge") ? true : orig.isPremium() }
}

class LEIADashboardPremiumHook: ClassHook<NSObject> {
    typealias Group = PremiumSpoofGroup
    static let targetName = "LINLEIADashboardConfig"
    func isPremium() -> Bool { LProPremiumState.flag("badge") ? true : orig.isPremium() }
}
