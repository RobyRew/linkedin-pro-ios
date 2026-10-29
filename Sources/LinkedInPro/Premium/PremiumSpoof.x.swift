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
    func canViewWVMP() -> NSNumber? { LProPremiumState.on ? LProPremiumState.yes : orig.canViewWVMP() }
    func canBrowseProfiles() -> NSNumber? { LProPremiumState.on ? LProPremiumState.yes : orig.canBrowseProfiles() }
    func canViewJobAnalytics() -> NSNumber? { LProPremiumState.on ? LProPremiumState.yes : orig.canViewJobAnalytics() }
    func canViewCompanyInsights() -> NSNumber? { LProPremiumState.on ? LProPremiumState.yes : orig.canViewCompanyInsights() }
    func canAccessLearningVideos() -> NSNumber? { LProPremiumState.on ? LProPremiumState.yes : orig.canAccessLearningVideos() }
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
    func premium() -> NSNumber? { LProPremiumState.on ? LProPremiumState.yes : orig.premium() }
    func showPremiumSubscriberBadge() -> NSNumber? {
        LProPremiumState.on ? LProPremiumState.yes : orig.showPremiumSubscriberBadge()
    }
}

class MePremiumHook: ClassHook<NSObject> {
    typealias Group = PremiumSpoofGroup
    static let targetName = "Me"
    func premiumSubscriber() -> NSNumber? { LProPremiumState.on ? LProPremiumState.yes : orig.premiumSubscriber() }
}

// MARK: - UI leaf gates (BOOL)

class FeedHeaderPremiumHook: ClassHook<NSObject> {
    typealias Group = PremiumSpoofGroup
    static let targetName = "LINFeedHeaderPresenterStyle"
    func shouldDisplayPremiumBar() -> Bool { LProPremiumState.on ? true : orig.shouldDisplayPremiumBar() }
    func shouldDisplayPremiumLogoV2() -> Bool { LProPremiumState.on ? true : orig.shouldDisplayPremiumLogoV2() }
}

class EntityCardPremiumHook: ClassHook<NSObject> {
    typealias Group = PremiumSpoofGroup
    static let targetName = "LINEntityCardData"
    func isPremium() -> Bool { LProPremiumState.on ? true : orig.isPremium() }
}

class LEIADashboardPremiumHook: ClassHook<NSObject> {
    typealias Group = PremiumSpoofGroup
    static let targetName = "LINLEIADashboardConfig"
    func isPremium() -> Bool { LProPremiumState.on ? true : orig.isPremium() }
}
