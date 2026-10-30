import Foundation

// Entries shown in the Premium settings panel. Names mirror the premium surface
// documented in PREMIUM-SURFACE.md / PREMIUM-ANALYSIS.md; the `id` values are
// stable so stored flags survive catalog changes. Each entry is a stored flag
// only - see PremiumOptions and PremiumEnabler.
enum PremiumFeatureCatalog {
    // What flipping a flag actually does, so the panel is honest (see
    // PREMIUM-SURFACE.md section 7). The client can flip its own gates; it cannot
    // produce data LinkedIn serves only to entitled members.
    enum Effect: String {
        // Wired to a precise on-device hook; the flag has a real local effect.
        case clientSide
        // The master client spoof can reveal the entry point / badge, but the
        // feature's data is served by LinkedIn and a local flag cannot unlock it.
        case serverGated

        var note: String {
            switch self {
            case .clientSide:  return "Takes effect on-device"
            case .serverGated: return "Entry/UI only \u{2014} LinkedIn serves the data"
            }
        }
    }

    struct Item {
        let id: String
        let title: String
        let symbol: String
        // Defaults to serverGated: most premium features are data LinkedIn gates
        // on its servers. Only the entries explicitly marked clientSide below are
        // wired to a local hook (membership cosmetics + the two suppressors).
        var effect: Effect = .serverGated
    }

    struct Group {
        let title: String
        let symbol: String
        let items: [Item]
    }

    // Flags wired to a precise client-side effect: the membership cosmetics and
    // the two suppressors (PremiumSpoof leaf gates / the upsell sweep / the
    // interstitial skip), plus the profile-editor features that the feature-aware
    // DashFeatureAccess gate unlocks for local use. Everything else is entry/UI
    // reveal only (its data is served by LinkedIn).
    static let clientSideIDs: Set<String> = [
        "badge", "bar", "logo", "subscriber_flag", "upsells", "interstitials",
        "spotlight", "featured", "profile_custom_cta", "profile_top_card_form", "unlimited_invite",
    ]

    static func isClientSide(_ id: String) -> Bool { clientSideIDs.contains(id) }

    static let groups: [Group] = [
        Group(title: "Membership", symbol: "crown", items: [
            Item(id: "badge", title: "Premium badge", symbol: "rosette", effect: .clientSide),
            Item(id: "bar", title: "Premium bar", symbol: "rectangle.topthird.inset.filled", effect: .clientSide),
            Item(id: "logo", title: "Premium logo", symbol: "star.square", effect: .clientSide),
            Item(id: "subscriber_flag", title: "Subscriber flag", symbol: "person.crop.circle.badge.checkmark", effect: .clientSide),
            Item(id: "storefront", title: "Premium storefront", symbol: "storefront"),
            Item(id: "upsells", title: "Hide upgrade prompts", symbol: "eye.slash", effect: .clientSide),
            Item(id: "interstitials", title: "Skip feature interstitials", symbol: "rectangle.on.rectangle.slash", effect: .clientSide),
        ]),
        Group(title: "Profile & network", symbol: "person.crop.circle", items: [
            // The viewer LIST is server data; the gate only reveals the section.
            Item(id: "wvmp", title: "Who viewed your profile", symbol: "eye"),
            Item(id: "wvmp_365", title: "365-day profile viewers", symbol: "calendar"),
            // Profile-editor features: unlocking the client gate makes them usable
            // (they save through the normal profile APIs), so they take effect locally.
            Item(id: "spotlight", title: "Profile spotlight", symbol: "sparkles", effect: .clientSide),
            Item(id: "featured", title: "Featured section", symbol: "square.grid.2x2", effect: .clientSide),
            Item(id: "profile_custom_cta", title: "Custom profile button", symbol: "cursorarrow.click", effect: .clientSide),
            Item(id: "profile_top_card_form", title: "Top-card premium settings", symbol: "rectangle.topthird.inset.filled", effect: .clientSide),
            Item(id: "unlimited_invite", title: "Custom invitation notes", symbol: "person.badge.plus", effect: .clientSide),
            Item(id: "profile_storefront", title: "Profile storefront", symbol: "storefront"),
        ]),
        Group(title: "InMail & messaging", symbol: "envelope", items: [
            Item(id: "inmail_credits", title: "InMail credits", symbol: "envelope.badge"),
            Item(id: "inmail_followups", title: "InMail follow-ups", symbol: "arrowshape.turn.up.right"),
            Item(id: "inmail_ai", title: "AI-assisted InMail", symbol: "wand.and.stars"),
            Item(id: "generated_messages", title: "Generated messages", symbol: "text.bubble"),
            Item(id: "away_messages", title: "Away messages", symbol: "moon.zzz"),
            Item(id: "subs_message_button", title: "Subscriber message button", symbol: "message.badge"),
            Item(id: "messaging_ai_entry", title: "Messaging AI entry point", symbol: "sparkle.magnifyingglass"),
            Item(id: "referral_boost", title: "Referral boost in chats", symbol: "arrow.up.circle"),
            Item(id: "referral_coupon", title: "Referral coupon in chats", symbol: "ticket"),
        ]),
        Group(title: "Jobs", symbol: "briefcase", items: [
            Item(id: "job_analytics", title: "Job analytics", symbol: "chart.bar"),
            Item(id: "applicant_insights", title: "Applicant insights", symbol: "person.text.rectangle"),
            Item(id: "top_applicant_insights", title: "Top applicant insights", symbol: "chart.bar.xaxis"),
            Item(id: "top_applicant_jobs", title: "Top applicant jobs", symbol: "star.circle"),
            Item(id: "top_choice", title: "Top choice", symbol: "star"),
            Item(id: "job_coach", title: "AI job coach", symbol: "brain.head.profile"),
            Item(id: "interview_prep", title: "Interview prep", symbol: "person.wave.2"),
            Item(id: "resume_keywords", title: "Resume keyword insights", symbol: "doc.text.magnifyingglass"),
            Item(id: "jobseeker_filters", title: "Job-seeker search filters", symbol: "line.3.horizontal.decrease"),
            Item(id: "how_you_match", title: "How you match: top skills", symbol: "checklist"),
            Item(id: "job_posting_company_insights", title: "Job posting company insights", symbol: "building.2.crop.circle"),
        ]),
        Group(title: "Company insights", symbol: "building.2", items: [
            Item(id: "company_insights", title: "Company insights", symbol: "chart.line.uptrend.xyaxis"),
            Item(id: "organization_company_insights", title: "Organization insights", symbol: "chart.bar.doc.horizontal"),
            Item(id: "competitor_insights", title: "Competitor insights", symbol: "chart.bar"),
            Item(id: "engagement_analytics", title: "Engagement analytics", symbol: "waveform.path.ecg"),
            Item(id: "insights_badge", title: "Insights badge", symbol: "rosette"),
            Item(id: "decision_makers", title: "Decision makers", symbol: "person.3"),
            Item(id: "follower_count_filter", title: "Follower-count search filter", symbol: "line.3.horizontal.decrease.circle"),
            Item(id: "alumni_insights", title: "Alumni insights", symbol: "graduationcap"),
        ]),
        Group(title: "Learning", symbol: "play.rectangle", items: [
            Item(id: "learning_videos", title: "Learning videos", symbol: "play.circle"),
            Item(id: "learning_badge", title: "Learning badge", symbol: "rosette"),
            Item(id: "learning_enterprise", title: "Enterprise learning", symbol: "building.columns"),
            Item(id: "lynda_premium", title: "Lynda premium", symbol: "books.vertical"),
        ]),
        Group(title: "Sales Navigator", symbol: "chart.bar.xaxis", items: [
            Item(id: "sales_nav_entry", title: "Sales Nav entry point", symbol: "arrow.up.right.square"),
            Item(id: "sales_nav_badge", title: "Sales Nav badge", symbol: "rosette"),
            Item(id: "relationship_explorer", title: "Relationship explorer", symbol: "point.3.connected.trianglepath.dotted"),
        ]),
        Group(title: "Recruiter & hiring", symbol: "person.badge.key", items: [
            Item(id: "recruiter_entry", title: "Recruiter entry point", symbol: "arrow.up.right.square"),
            Item(id: "recruiter_mailbox", title: "Recruiter mailbox", symbol: "tray.full"),
            Item(id: "recruiter_message", title: "Recruiter message button", symbol: "message"),
            Item(id: "hiring_manager_mailbox", title: "Hiring manager mailbox", symbol: "tray.2"),
            Item(id: "hiring_agent", title: "Hiring agent", symbol: "cpu"),
        ]),
        Group(title: "Pages", symbol: "rectangle.3.group.bubble", items: [
            Item(id: "premium_page", title: "Premium Page", symbol: "rectangle.stack.badge.plus"),
            Item(id: "premium_page_plus", title: "Premium Page Plus", symbol: "rectangle.stack.badge.plus"),
            Item(id: "premium_page_pro", title: "Premium Page Pro", symbol: "rectangle.stack.badge.plus"),
            Item(id: "premium_page_trial", title: "Premium Page trial", symbol: "clock.arrow.circlepath"),
            Item(id: "pages_auto_invite", title: "Pages auto-invite", symbol: "person.badge.plus"),
            Item(id: "pages_credits", title: "Pages additional credits", symbol: "creditcard"),
            Item(id: "pages_invite_follow", title: "Pages invite-to-follow", symbol: "bell.badge"),
        ]),
        Group(title: "AI & writing", symbol: "wand.and.stars", items: [
            Item(id: "premium_coach", title: "Premium coach", symbol: "brain"),
            Item(id: "writing_assistant", title: "Writing assistant", symbol: "pencil.and.outline"),
            Item(id: "generated_profile_content", title: "Generated profile content", symbol: "doc.badge.gearshape"),
        ]),
        Group(title: "Growth & marketplace", symbol: "megaphone", items: [
            Item(id: "member_boosting", title: "Member post boosting", symbol: "bolt"),
            Item(id: "small_business_boosting", title: "Small-business post boosting", symbol: "bolt.circle"),
            Item(id: "advertise_badge", title: "Advertise badge", symbol: "megaphone"),
            Item(id: "service_marketplace_promo", title: "Service marketplace promo", symbol: "storefront"),
            Item(id: "service_provider_leads", title: "Service provider leads", symbol: "person.2.wave.2"),
            Item(id: "rfs_matching", title: "RFS marketplace matching", symbol: "arrow.triangle.branch"),
        ]),
        Group(title: "My Premium & commerce", symbol: "creditcard", items: [
            Item(id: "my_premium", title: "My Premium page", symbol: "person.crop.square"),
            Item(id: "my_premium_v2", title: "My Premium v2", symbol: "person.crop.square.badge.camera"),
            Item(id: "restore_purchase", title: "Restore purchase", symbol: "arrow.clockwise"),
            Item(id: "subscription_switcher", title: "Subscription switcher", symbol: "arrow.left.arrow.right"),
            Item(id: "cancellation_flow", title: "Cancellation flow", symbol: "xmark.circle"),
            Item(id: "onboarding_flow", title: "Onboarding flow", symbol: "figure.walk"),
            Item(id: "premium_gifting", title: "Premium gifting", symbol: "gift"),
            Item(id: "redeem", title: "Redeem", symbol: "ticket"),
            Item(id: "referrals", title: "Referrals", symbol: "person.2.badge.plus"),
            Item(id: "two_sided_referrals", title: "Two-sided referrals", symbol: "person.2.badge.gearshape"),
        ]),
    ]
}
