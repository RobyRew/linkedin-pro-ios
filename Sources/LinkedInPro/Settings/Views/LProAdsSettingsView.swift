import SwiftUI

// Ads & sponsored settings. These options are app-wide: the SDUI feed filter
// drops cards before they are built, and the shared LProViewSweeper hides
// sponsored / promoted chrome on every other screen.
struct LProAdsSettingsView: View {
    @State private var options = UserDefaults.lproFeedFilter

    var body: some View {
        List {
            Section {
                Toggle(isOn: $options.hideSponsored) {
                    Label("Hide sponsored posts (Promoted)", systemImage: "megaphone")
                }
                Toggle(isOn: $options.hidePromotions) {
                    Label("Hide promotions & suggestions", systemImage: "sparkles.rectangle.stack")
                }
                Toggle(isOn: $options.hidePremiumUpsell) {
                    Label("Hide Premium upselling", systemImage: "crown")
                }
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
