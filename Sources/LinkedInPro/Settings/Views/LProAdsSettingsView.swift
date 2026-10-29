import SwiftUI

// Ads & sponsored settings. These options are app-wide: the SDUI feed filter
// drops cards before they are built, and the view sweep in LProAds hides
// sponsored / promoted chrome on every other screen.
struct LProAdsSettingsView: View {
    @State private var options = UserDefaults.lproFeedFilter

    var body: some View {
        List {
            Section {
                Toggle("Hide sponsored posts (Promoted)", isOn: $options.hideSponsored)
                Toggle("Hide promotions & suggestions", isOn: $options.hidePromotions)
                Toggle("Hide Premium upselling", isOn: $options.hidePremiumUpsell)
            } header: {
                Text("Ads & sponsored")
            } footer: {
                Text("Applies across the app, not only the feed: sponsored cards, \u{201C}Promoted\u{201D} posts, suggestion carousels and Premium upsell banners. The feed filter removes cards before layout; other screens are swept as they appear.")
            }
        }
        .navigationTitle("Ads & Sponsored")
        .onChange(of: options) { _, newValue in
            UserDefaults.lproFeedFilter = newValue
        }
    }
}
