import SwiftUI

// Premium settings. The client spoof is the master switch; under it, each feature
// group lists flags that refine what the spoof reveals. Every flag states what it
// actually does on-device - "Takes effect on-device" for the wired client-side
// ones (membership cosmetics + the two suppressors), "Entry/UI only" for the rest,
// whose data LinkedIn serves to entitled members only. Stored in
// UserDefaults.lproPremium; PremiumEnabler applies a change.
struct LProPremiumSettingsView: View {
    @State private var options = UserDefaults.lproPremium
    // "Hide upgrade prompts" (id "upsells") is the same setting as the Ads panel's
    // "Hide Premium upselling" - both read/write lproFeedFilter.hidePremiumUpsell.
    @State private var feed = UserDefaults.lproFeedFilter

    var body: some View {
        List {
            Section {
                Toggle(isOn: $options.spoofPremium) {
                    Label("Spoof Premium (client flags)", systemImage: "crown.fill")
                }
            } header: {
                Text("Client spoof")
            } footer: {
                Text("Flips the client's premium flags: gold badge, premium bars and logos, suppressed upgrade prompts, premium entry points. LinkedIn still checks premium on its servers for the data itself, so who-viewed-me lists, analytics, InMail credits and Learning streams stay gated. Turn this off to disable every flag below at once.")
            }

            Section {
                Toggle(isOn: masterBinding) {
                    Label("All features", systemImage: "square.stack.3d.up")
                }
                LabeledContent("Enabled", value: "\(options.enabledCount)/\(options.featureCount)")
            } footer: {
                Text("Switches every flag below on or off together. Each can still be changed on its own inside its group.")
            }

            ForEach(PremiumFeatureCatalog.groups, id: \.title) { group in
                DisclosureGroup {
                    ForEach(group.items, id: \.id) { item in
                        Toggle(isOn: binding(item.id)) {
                            VStack(alignment: .leading, spacing: 2) {
                                Label(item.title, systemImage: item.symbol)
                                Text(item.effect.note)
                                    .font(.caption2)
                                    .foregroundStyle(item.effect == .clientSide ? Color.green : .secondary)
                            }
                        }
                        .disabled(!options.spoofPremium && item.id != "upsells")
                    }
                } label: {
                    Label(group.title, systemImage: group.symbol)
                }
            }
        }
        .navigationTitle("Premium")
        .onChange(of: options) { _, newValue in
            UserDefaults.lproPremium = newValue
            PremiumEnabler.sync(newValue)
        }
        .onChange(of: feed) { _, newValue in
            UserDefaults.lproFeedFilter = newValue
            LProViewSweeper.schedule()
        }
    }

    // Master switch: reflects "every option on", and sets them all.
    private var masterBinding: Binding<Bool> {
        Binding(
            get: { options.allEnabled },
            set: { on in options.setAll(on) }
        )
    }

    private func binding(_ id: String) -> Binding<Bool> {
        if id == "upsells" {
            // Shared with the Ads panel; backed by lproFeedFilter, not the spoof.
            return Binding(
                get: { feed.hidePremiumUpsell },
                set: { on in feed.hidePremiumUpsell = on }
            )
        }
        return Binding(
            get: { options.isEnabled(id) },
            set: { on in options.set(id, on) }
        )
    }
}
