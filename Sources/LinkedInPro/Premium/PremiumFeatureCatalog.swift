import Foundation

// Entries shown in the Premium settings panel. Names come from the premium
// surface documented in PREMIUM-SURFACE.md. Each entry is a stored flag; see
// PremiumOptions - nothing enforces them.
enum PremiumFeatureCatalog {
    struct Item {
        let id: String
        let title: String
        let symbol: String
    }

    struct Group {
        let title: String
        let symbol: String
        let items: [Item]
    }

    static let groups: [Group] = [
        Group(title: "Membership", symbol: "crown", items: [
            Item(id: "badge", title: "Premium badge", symbol: "rosette"),
            Item(id: "bar", title: "Premium bar", symbol: "rectangle.topthird.inset.filled"),
            Item(id: "logo", title: "Premium logo", symbol: "star.square"),
            Item(id: "upsells", title: "Hide upgrade prompts", symbol: "eye.slash"),
            Item(id: "interstitials", title: "Skip feature interstitials", symbol: "rectangle.on.rectangle.slash"),
        ]),
        Group(title: "InMail", symbol: "envelope", items: [
            Item(id: "inmail_credits", title: "InMail credits", symbol: "envelope.badge"),
            Item(id: "inmail_followups", title: "InMail follow-ups", symbol: "arrowshape.turn.up.right"),
            Item(id: "inmail_ai", title: "AI-assisted InMail", symbol: "wand.and.stars"),
        ]),
        Group(title: "Profile", symbol: "person.crop.circle", items: [
            Item(id: "wvmp", title: "Who viewed your profile", symbol: "eye"),
            Item(id: "wvmp_365", title: "365-day profile viewers", symbol: "calendar"),
            Item(id: "spotlight", title: "Profile spotlight", symbol: "sparkles"),
            Item(id: "featured", title: "Featured section", symbol: "square.grid.2x2"),
        ]),
        Group(title: "Jobs", symbol: "briefcase", items: [
            Item(id: "job_analytics", title: "Job analytics", symbol: "chart.bar"),
            Item(id: "applicant_insights", title: "Applicant insights", symbol: "person.text.rectangle"),
            Item(id: "top_choice", title: "Top choice", symbol: "star"),
            Item(id: "job_coach", title: "AI job coach", symbol: "brain.head.profile"),
        ]),
        Group(title: "Company insights", symbol: "building.2", items: [
            Item(id: "company_insights", title: "Company insights", symbol: "chart.line.uptrend.xyaxis"),
            Item(id: "competitor_insights", title: "Competitor insights", symbol: "chart.bar.doc.horizontal"),
            Item(id: "alumni_insights", title: "Alumni insights", symbol: "graduationcap"),
        ]),
        Group(title: "Learning", symbol: "play.rectangle", items: [
            Item(id: "learning_videos", title: "Learning videos", symbol: "play.circle"),
            Item(id: "learning_badge", title: "Learning badge", symbol: "rosette"),
            Item(id: "learning_enterprise", title: "Enterprise learning", symbol: "building.columns"),
        ]),
        Group(title: "Sales Navigator", symbol: "chart.bar.xaxis", items: [
            Item(id: "sales_nav_entry", title: "Sales Nav entry point", symbol: "arrow.up.right.square"),
            Item(id: "sales_nav_badge", title: "Sales Nav badge", symbol: "rosette"),
            Item(id: "relationship_explorer", title: "Relationship explorer", symbol: "point.3.connected.trianglepath.dotted"),
        ]),
        Group(title: "Recruiter", symbol: "person.badge.key", items: [
            Item(id: "recruiter_entry", title: "Recruiter entry point", symbol: "arrow.up.right.square"),
            Item(id: "recruiter_mailbox", title: "Recruiter mailbox", symbol: "tray.full"),
            Item(id: "recruiter_message", title: "Recruiter message button", symbol: "message"),
        ]),
        Group(title: "My Premium", symbol: "creditcard", items: [
            Item(id: "my_premium", title: "My Premium page", symbol: "person.crop.square"),
            Item(id: "restore_purchase", title: "Restore purchase", symbol: "arrow.clockwise"),
        ]),
    ]
}
