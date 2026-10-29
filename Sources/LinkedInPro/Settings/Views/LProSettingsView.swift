import SwiftUI

// The tweak's settings screen, hosted by LProSettingsViewController and pushed
// onto LinkedIn's own navigation stack. Plain native SwiftUI; it picks up the
// iOS 26 Liquid Glass styling once the nav-bar feature flips LinkedIn's design
// opt-out (Phase 3). Feature sections fill in per phase.
struct LProSettingsView: View {
    @State private var devKit = UserDefaults.standard.bool(forKey: LProSettingsKeys.devKit)

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
                comingSoon("Navigation Bar", systemImage: "square.grid.3x3.fill.square",
                           detail: "Reorder / hide tabs; Liquid Glass on iOS 26")
            }

            Section {
                Toggle(isOn: $devKit) {
                    Label("DevKit console (Striker)", systemImage: "terminal")
                }
                .onChange(of: devKit) { _, newValue in
                    UserDefaults.standard.set(newValue, forKey: LProSettingsKeys.devKit)
                }
            } header: {
                Text("Developer")
            } footer: {
                Text("Exposes the Striker introspection console over USB on relaunch. Leave off unless you are debugging.")
            }

            Section {
                LabeledContent("Build", value: GeneratedConfig.buildStamp)
                LabeledContent("Commit", value: GeneratedConfig.commit)
            }
        }
        .navigationTitle("LinkedIn Professional")
    }

    private func comingSoon(_ title: String, systemImage: String, detail: String) -> some View {
        HStack {
            Label { Text(title) } icon: { Image(systemName: systemImage) }
            Spacer()
            Text("Soon").font(.caption).foregroundStyle(.secondary)
        }
        .foregroundStyle(.secondary)
        .accessibilityHint(detail)
    }
}
