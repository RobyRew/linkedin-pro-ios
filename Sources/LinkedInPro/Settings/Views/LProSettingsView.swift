import SwiftUI

// The tweak's settings screen, hosted by LProSettingsViewController and pushed
// onto LinkedIn's own navigation stack. Plain native SwiftUI; it picks up the
// iOS 26 Liquid Glass styling once the nav-bar feature flips LinkedIn's design
// opt-out (Phase 3). Feature sections fill in per phase.
struct LProSettingsView: View {
    @State private var devKit = LProDevKit.isEnabled

    var body: some View {
        List {
            Section {
                HStack(spacing: 12) {
                    Image(systemName: "briefcase.fill")
                        .font(.title2)
                        .foregroundStyle(.tint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("LinkedIn Professional").font(.headline)
                        Text("Customization for LinkedIn").font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Features") {
                NavigationLink {
                    LProFeedSettingsView()
                } label: {
                    Label("Feed", systemImage: "list.bullet.rectangle")
                }
                NavigationLink {
                    LProNavBarSettingsView()
                } label: {
                    Label("Navigation Bar", systemImage: "square.grid.3x3.fill.square")
                }
            }

            Section {
                Toggle(isOn: $devKit) {
                    Label("DevKit console (Striker)", systemImage: "terminal")
                }
                .onChange(of: devKit) { _, newValue in
                    LProDevKit.setEnabled(newValue)
                }
                LabeledContent("Status") {
                    Text(devKit ? "Listening on 127.0.0.1:\(LProDevKit.port)" : "Off")
                        .foregroundStyle(devKit ? .green : .secondary)
                        .font(.footnote.monospaced())
                }
            } header: {
                Text("Developer")
            } footer: {
                Text("The Striker introspection console, reachable over USB with `iproxy \(LProDevKit.port) \(LProDevKit.port)`. Starting/stopping here takes effect immediately.")
            }

            Section("Versions") {
                LabeledContent("LinkedIn", value: "\(LinkedInVersion.short) (\(LinkedInVersion.build))")
                LabeledContent("LinkedIn Professional", value: "\(GeneratedConfig.tweakVersion) (\(GeneratedConfig.commit))")
                LabeledContent("Build", value: GeneratedConfig.buildStamp)
            }
        }
        .navigationTitle("LinkedIn Professional")
    }
}
