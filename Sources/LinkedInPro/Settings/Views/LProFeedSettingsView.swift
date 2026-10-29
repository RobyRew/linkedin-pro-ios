import SwiftUI

// Feed filter settings. Writes back to UserDefaults.lproFeedFilter, which
// FeedFilter.x.swift reads on each decode and the premium-hide hook reads on
// each screen.
struct LProFeedSettingsView: View {
    @State private var options = UserDefaults.lproFeedFilter

    var body: some View {
        List {
            Section("Clean up the feed") {
                Toggle("Hide ads (Promoted)", isOn: $options.hideSponsored)
                Toggle("Hide promotions & suggestions", isOn: $options.hidePromotions)
                Toggle("Hide Premium upselling", isOn: $options.hidePremiumUpsell)
            }

            Section {
                Toggle("Hide reaction-surfaced posts", isOn: $options.hideReactionSurfaced)
                Toggle("Hide comment-surfaced posts", isOn: $options.hideCommentSurfaced)
            } header: {
                Text("Surfaced by your network")
            } footer: {
                Text("Hides posts that appear only because someone in your network reacted to (\u{201C}\u{2026} likes this\u{201D}) or commented on (\u{201C}\u{2026} commented on this\u{201D}) them, not posts people you follow authored.")
            }

            if options.hideReactionSurfaced {
                Section("Hide which reactions") {
                    ForEach(LProReaction.allCases, id: \.self) { reaction in
                        Toggle(isOn: binding(for: reaction)) {
                            Label(reaction.displayName, systemImage: reaction.symbol)
                        }
                    }
                }
            }
        }
        .navigationTitle("Feed")
        .onChange(of: options) { _, newValue in
            UserDefaults.lproFeedFilter = newValue
        }
    }

    private func binding(for reaction: LProReaction) -> Binding<Bool> {
        Binding(
            get: { options.reactions.contains(reaction) },
            set: { isOn in
                if isOn { options.reactions.insert(reaction) } else { options.reactions.remove(reaction) }
            }
        )
    }
}
