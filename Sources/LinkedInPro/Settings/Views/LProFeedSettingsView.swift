import SwiftUI

// Feed filter settings: a master switch plus per-reaction toggles. Writes back to
// UserDefaults.lproFeedFilter, which FeedFilter.x.swift reads on each decode.
struct LProFeedSettingsView: View {
    @State private var options = UserDefaults.lproFeedFilter

    var body: some View {
        List {
            Section {
                Toggle("Hide reaction-surfaced posts", isOn: $options.hideReactionSurfaced)
            } footer: {
                Text("Hides posts that appear only because someone in your network reacted to them (the \u{201C}\u{2026} likes this\u{201D} posts), not posts people you follow actually authored.")
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
