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
    static let yes = NSNumber(value: true)
    static let no = NSNumber(value: false)

    // When the user is hiding premium upselling, report the trial / reactivation /
    // upgrade ELIGIBILITY gates as not-eligible so the app never GENERATES the
    // "Try Premium for €0" offers in the first place (the view sweep then has far
    // less to catch). A spoofed premium member is not trial-eligible anyway, so
    // this is consistent. Reads UserDefaults directly (not the main-thread feed
    // cache): these gates can be evaluated off the main thread and are not a
    // per-card hot path.
    static var suppressUpsellOffers: Bool { UserDefaults.lproFeedFilter.hidePremiumUpsell }

    // UserDefaults.lproPremium decodes a JSON blob on every read, and the premium
    // hooks (especially the hot hasAccess gate) read it per call - so cache the
    // decoded options and refresh only when the panel writes (PremiumEnabler.sync
    // calls invalidate()).
    private static var cache: PremiumOptions?
    static var options: PremiumOptions {
        if let c = cache { return c }
        let o = UserDefaults.lproPremium
        cache = o
        return o
    }
    static func invalidate() { cache = nil }

    static var on: Bool { options.spoofPremium }

    // A specific surface is spoofed when the master spoof is on AND that surface's
    // flag is enabled (a missing flag defaults on). This lets the per-feature
    // toggles in the Premium panel actually gate individual surfaces, while the
    // master switch still governs everything.
    static func flag(_ id: String) -> Bool { on && options.isEnabled(id) }

    // Best-effort read of a DashFeatureAccess record's access-type symbol (e.g.
    // "CAN_ACCESS_PROFILE_PREMIUM_SPOTLIGHT"), used to make the generic hasAccess
    // gate honour per-feature toggles. Handles a string-backed enum as well as an
    // object wrapper; returns nil on any uncertainty so the caller falls back to
    // the master behaviour (grant), never a regression.
    static func accessTypeSymbol(of obj: NSObject) -> String? {
        let typeSel = "featureAccessType"
        guard obj.responds(to: NSSelectorFromString(typeSel)) else { return nil }
        let raw = obj.value(forKey: typeSel)
        if let s = raw as? String, !s.isEmpty { return s }   // string-backed enum
        guard let type = raw as? NSObject else { return nil }
        for key in ["name", "value", "rawValue", "stringValue"] {
            if type.responds(to: NSSelectorFromString(key)),
               let s = type.value(forKey: key) as? String, !s.isEmpty { return s }
        }
        return nil
    }
}

// Maps a DashFeatureAccess access-type symbol to the catalog flag that governs it,
// so a per-feature toggle withholds that access type. The match is by FAMILY, not
// exact symbol: a needle like "COMPANY" covers the whole company-insights family
// (organization / job-posting company included), so turning one family's toggle
// off withholds its siblings too. First match wins, most-specific needles first;
// an unmapped (or unreadable) type is left to the master spoof, i.e. granted.
enum PremiumAccessTypeMap {
    private static let rules: [(needle: String, id: String)] = [
        ("WHO_VIEWED", "wvmp"), ("WVMP", "wvmp"), ("BROWSE_MAP", "wvmp"), ("BROWSE", "wvmp"),
        ("SPOTLIGHT", "spotlight"),
        ("FEATURED", "featured"),
        ("CUSTOM_ACTION", "profile_custom_cta"), ("CUSTOM_CTA", "profile_custom_cta"), ("CUSTOM_BUTTON", "profile_custom_cta"),
        ("TOP_CARD_FORM", "profile_top_card_form"),
        ("UNLIMITED", "unlimited_invite"),
        ("PROFILE_STOREFRONT", "profile_storefront"),
        ("MY_PREMIUM_V2", "my_premium_v2"), ("MY_PREMIUM", "my_premium"),
        ("JOB_COACH", "job_coach"), ("JOB_ANALYTICS", "job_analytics"),
        ("APPLICANT", "applicant_insights"), ("TOP_CHOICE", "top_choice"),
        ("COMPETITOR", "competitor_insights"), ("COMPANY", "company_insights"),
        ("LEARNING", "learning_videos"), ("LYNDA", "lynda_premium"),
        ("INMAIL", "inmail_credits"),
        ("SALES_NAV", "sales_nav_entry"), ("RELATIONSHIP_EXPLORER", "relationship_explorer"),
        ("RECRUITER", "recruiter_entry"),
        ("PREMIUM_PAGE_PLUS", "premium_page_plus"), ("PREMIUM_PAGE_PRO", "premium_page_pro"), ("PREMIUM_PAGE", "premium_page"),
        ("PREMIUM_COACH", "premium_coach"),
        ("REFERRAL", "referrals"),
    ]

    static func flag(forAccessType raw: String) -> String? {
        let u = raw.uppercased()
        for (needle, id) in rules where u.contains(needle) { return id }
        return nil
    }
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

    // Eligibility-for-offer gates (confirmed present on this build, NSNumber-backed).
    // Forced not-eligible while upselling is hidden, so "Try Premium" offers are not
    // produced; otherwise left to LinkedIn. These do NOT grant a capability.
    func premiumFreeTrialEligible() -> NSNumber? {
        LProPremiumState.suppressUpsellOffers ? LProPremiumState.no : orig.premiumFreeTrialEligible()
    }
    func reactivationFeaturesEligible() -> NSNumber? {
        LProPremiumState.suppressUpsellOffers ? LProPremiumState.no : orig.reactivationFeaturesEligible()
    }
    func premiumLearningUpgradeEligible() -> NSNumber? {
        LProPremiumState.suppressUpsellOffers ? LProPremiumState.no : orig.premiumLearningUpgradeEligible()
    }
}

class DashFeatureAccessHook: ClassHook<NSObject> {
    typealias Group = PremiumSpoofGroup
    static let targetName = "DashFeatureAccess"
    // Feature-aware: with the master spoof on, grant every access type EXCEPT one
    // whose mapped per-feature family toggle has been turned off (see
    // PremiumAccessTypeMap - the match is by family, so a withheld toggle also
    // withholds its siblings). Any access type we cannot read or map is granted,
    // matching the old always-grant behaviour, so a FALSE grant of a
    // master-disabled feature never happens.
    func hasAccess() -> NSNumber? {
        guard LProPremiumState.on else { return orig.hasAccess() }
        if let symbol = LProPremiumState.accessTypeSymbol(of: target),
           let id = PremiumAccessTypeMap.flag(forAccessType: symbol),
           !LProPremiumState.options.isEnabled(id) {
            return orig.hasAccess()
        }
        return LProPremiumState.yes
    }
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
