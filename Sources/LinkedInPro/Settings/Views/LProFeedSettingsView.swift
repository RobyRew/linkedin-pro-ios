import SwiftUI

// Feed filter settings. Writes back to UserDefaults.lproFeedFilter, which
// FeedFilter.x.swift reads on each decode and SDUIFeedFilter reads per card.
struct LProFeedSettingsView: View {
    @State private var options = UserDefaults.lproFeedFilter
    @State private var statsTick = 0

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
                Toggle("Hide reposted posts", isOn: $options.hideRepostSurfaced)
            } header: {
                Text("Surfaced by your network")
            } footer: {
                Text("Hides posts that appear only because someone in your network reacted to (\u{201C}\u{2026} finds this funny\u{201D}), commented on (\u{201C}\u{2026} commented on this\u{201D}) or reposted (\u{201C}\u{2026} reposted this\u{201D}) them, not posts people you follow authored.")
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

            Section {
                if stats.isEmpty {
                    Text("No cards hidden yet this session.")
                        .font(.footnote).foregroundStyle(.secondary)
                } else {
                    ForEach(stats, id: \.reason) { row in
                        LabeledContent(displayName(row.reason), value: "\(row.count)")
                    }
                    Button("Clear") {
                        SDUIFeedStats.reset()
                        statsTick += 1
                    }
                }
            } header: {
                Text("This session")
            } footer: {
                Text("Cards the feed filter removed since the app launched. A category that stays at zero may mean its marker changed in this LinkedIn build.")
            }
            .id(statsTick)
        }
        .navigationTitle("Feed")
        .onChange(of: options) { _, newValue in
            UserDefaults.lproFeedFilter = newValue
        }
    }

    private var stats: [(reason: String, count: Int)] { SDUIFeedStats.summary }

    private func binding(for reaction: LProReaction) -> Binding<Bool> {
        Binding(
            get: { options.reactions.contains(reaction) },
            set: { isOn in
                if isOn { options.reactions.insert(reaction) } else { options.reactions.remove(reaction) }
            }
        )
    }

    private func displayName(_ reason: String) -> String {
        if reason.hasPrefix("reaction-") {
            let raw = String(reason.dropFirst("reaction-".count))
            return "Reaction: " + (LProReaction(rawValue: raw)?.displayName ?? raw)
        }
        switch reason {
        case "sponsored": return "Ads (Promoted)"
        case "promotion": return "Promotions & suggestions"
        case "premium-upsell": return "Premium upsells"
        case "commented": return "Comment-surfaced posts"
        case "reposted": return "Reposted posts"
        default: return reason
        }
    }
}
