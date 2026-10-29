import SwiftUI

// Premium settings: a master switch over collapsible feature groups, plus the
// client spoof toggle. Every feature flag is stored in UserDefaults.lproPremium
// and reported to PremiumPOC.sync(); see PremiumOptions for what backs them.
struct LProPremiumSettingsView: View {
    @State private var options = UserDefaults.lproPremium

    var body: some View {
        List {
            Section {
                Toggle("Premium features", isOn: masterBinding)
                LabeledContent("Enabled", value: "\(options.enabledCount)/\(options.featureCount)")
            } header: {
                Text("All features")
            } footer: {
                Text("Switches every option below on or off together. Each option can still be changed on its own inside its group.")
            }

            ForEach(PremiumFeatureCatalog.groups, id: \.title) { group in
                DisclosureGroup {
                    ForEach(group.items, id: \.id) { item in
                        Toggle(isOn: binding(item.id)) {
                            Label(item.title, systemImage: item.symbol)
                        }
                    }
                } label: {
                    Label(group.title, systemImage: group.symbol)
                }
            }

            Section {
                Toggle("Spoof Premium (client flags)", isOn: $options.spoofPremium)
            } header: {
                Text("Client")
            } footer: {
                Text("Flips the client's premium flags: gold badge, premium bars and logos, suppressed upgrade prompts, premium entry points. LinkedIn still checks premium on its servers for the data itself, so who-viewed-me lists, analytics, InMail credits and Learning streams stay gated.")
            }
        }
        .navigationTitle("Premium")
        .onChange(of: options) { _, newValue in
            UserDefaults.lproPremium = newValue
            PremiumPOC.sync(newValue)
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
        Binding(
            get: { options.isEnabled(id) },
            set: { on in options.set(id, on) }
        )
    }
}
