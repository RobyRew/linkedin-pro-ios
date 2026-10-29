import SwiftUI

// Premium spoof settings. Writes UserDefaults.lproPremium, read by PremiumSpoof.
struct LProPremiumSettingsView: View {
    @State private var options = UserDefaults.lproPremium

    var body: some View {
        List {
            Section {
                Toggle("Spoof Premium", isOn: $options.spoofPremium)
            } header: {
                Text("Premium")
            } footer: {
                Text("Flips the client's premium flags so premium UI unlocks: the gold badge, premium bars/logos, hidden \u{201C}upgrade\u{201D} prompts, and the premium feature entry points.")
            }

            Section {
                Text("What this does NOT do")
                    .font(.footnote.weight(.semibold))
                Text("LinkedIn still checks premium on its servers for the actual data. Who-viewed-me lists, profile/company analytics, InMail credits and Learning videos stay gated - you get the premium screens, but they come back empty or ask to subscribe. Takes effect on relaunch.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Premium")
        .onChange(of: options) { _, newValue in
            UserDefaults.lproPremium = newValue
        }
    }
}
