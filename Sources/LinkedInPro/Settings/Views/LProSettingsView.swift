import SwiftUI

// The tweak's settings screen, hosted by LProSettingsViewController and pushed
// onto LinkedIn's own navigation stack. Plain native SwiftUI; it picks up the
// iOS 26 Liquid Glass styling once the nav-bar feature flips LinkedIn's design
// opt-out (Phase 3). Feature sections fill in per phase.
struct LProSettingsView: View {
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
                    LProAdsSettingsView()
                } label: {
                    Label("Ads & Sponsored", systemImage: "megaphone")
                }
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
                NavigationLink {
                    LProPremiumSettingsView()
                } label: {
                    Label("Premium", systemImage: "crown")
                }
            }

            Section {
                LabeledContent {
                    Text(LProDevKit.isEnabled ? "On · 127.0.0.1:\(LProDevKit.port)" : "Off")
                        .foregroundStyle(LProDevKit.isEnabled ? .green : .secondary)
                        .font(.footnote.monospaced())
                } label: {
                    Label("DevKit console (Striker)", systemImage: "terminal")
                }
            } header: {
                Text("Developer")
            } footer: {
                Text("The Striker introspection console is always on for this build (loopback only), reachable over USB with `iproxy \(LProDevKit.port) \(LProDevKit.port)`; it answers while LinkedIn is in the foreground. Build it with -DLPRO_DEVKIT_OFF, or drop a LPRO_DEVKIT_OFF file in the app's Documents, to ship without it.")
            }

            Section("Versions") {
                LabeledContent("LinkedIn", value: "\(LinkedInVersion.short) (\(LinkedInVersion.build))")
                LabeledContent("LinkedIn Professional", value: "\(GeneratedConfig.tweakVersion) (\(GeneratedConfig.commit))")
                LabeledContent("Build", value: GeneratedConfig.buildStamp)
            }

            Section {
                Link(destination: URL(string: "https://github.com/RobyRew/linkedin-pro-ios")!) {
                    LabeledContent("Source", value: "RobyRew/linkedin-pro-ios")
                }
                Link(destination: URL(string: "https://github.com/RobyRew")!) {
                    LabeledContent("Made by", value: "RobyRew")
                }
            } header: {
                Text("About")
            } footer: {
                Text("LinkedIn Professional is an independent customization tweak. Not affiliated with LinkedIn.")
            }
        }
        .navigationTitle("LinkedIn Professional")
    }
}
