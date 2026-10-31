import SwiftUI

// The tweak's settings screen, hosted by LProSettingsViewController and shown on a
// UIKit navigation controller (pushed onto LinkedIn's own stack, or the root of a
// modally-presented one). SwiftUI NavigationLink needs a SwiftUI NavigationStack
// ancestor, which this flow has not got, so the feature rows push their sub-screen
// through UIKit instead (the `push` closure) - one native nav bar, native back,
// works from either entry path.

// Liquid Glass surface on iOS 26+, a plain rounded fill below it. Keeps the tweak
// settings looking current even though LinkedIn's bundle opts out of the design
// system.
private struct LProGlassCard: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular, in: .rect(cornerRadius: 20))
        } else {
            content.background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemBackground))
            )
        }
    }
}

// A rounded, tinted icon tile - the familiar modern iOS settings row glyph.
private struct LProIconTile: View {
    let symbol: String
    let tint: Color
    var size: CGFloat = 30
    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
            .fill(tint.gradient)
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: size * 0.5, weight: .semibold))
                    .foregroundStyle(.white)
            )
            .accessibilityHidden(true)
    }
}

// A tappable feature row: tinted tile + title + subtitle + disclosure chevron.
// Uses the UIKit push closure rather than NavigationLink.
private struct LProNavRow: View {
    let title: String
    let subtitle: String
    let symbol: String
    let tint: Color
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                LProIconTile(symbol: symbol, tint: tint)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).foregroundStyle(.primary)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.forward")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct LProSettingsView: View {
    // Pushes a sub-screen onto the hosting UIKit navigation controller.
    let push: (AnyView, String) -> Void
    @State private var devKit = LProDevKit.isEnabled

    var body: some View {
        List {
            // Header card
            Section {
                HStack(spacing: 14) {
                    LProIconTile(symbol: "briefcase.fill", tint: .blue, size: 46)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("LinkedIn Professional").font(.headline)
                        Text("Customization for LinkedIn")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .modifier(LProGlassCard())
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color.clear)
            }

            Section("Features") {
                LProNavRow(title: "Ads & Sponsored",
                           subtitle: "Hide promoted posts and upsells",
                           symbol: "megaphone.fill", tint: .orange) {
                    push(AnyView(LProAdsSettingsView()), "Ads & Sponsored")
                }
                LProNavRow(title: "Feed",
                           subtitle: "Filter reaction, comment and repost posts",
                           symbol: "list.bullet.rectangle.fill", tint: .green) {
                    push(AnyView(LProFeedSettingsView()), "Feed")
                }
                LProNavRow(title: "Navigation Bar",
                           subtitle: "Reorder, hide, icons, Liquid Glass",
                           symbol: "square.grid.3x3.fill", tint: .indigo) {
                    push(AnyView(LProNavBarSettingsView()), "Navigation Bar")
                }
                LProNavRow(title: "Premium",
                           subtitle: "Spoof premium and unlock client features",
                           symbol: "crown.fill", tint: .yellow) {
                    push(AnyView(LProPremiumSettingsView()), "Premium")
                }
            }

            Section {
                Toggle(isOn: $devKit) {
                    HStack(spacing: 12) {
                        LProIconTile(symbol: "terminal.fill", tint: .gray)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("DevKit console (Striker)")
                            Text(devKit ? "On · 127.0.0.1:\(LProDevKit.port)" : "Off")
                                .font(.caption.monospaced())
                                .foregroundStyle(devKit ? .green : .secondary)
                        }
                    }
                }
                .onChange(of: devKit) { _, on in LProDevKit.setEnabled(on) }

                Button {
                    push(AnyView(LProStrikerConsoleView()), "Striker console")
                } label: {
                    HStack(spacing: 12) {
                        LProIconTile(symbol: "text.line.first.and.arrowtriangle.forward", tint: .gray)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Remote command console").foregroundStyle(.primary)
                            Text("Live view of commands and their output")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.forward")
                            .font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } header: {
                Text("Developer")
            } footer: {
                Text("Loopback introspection console. Reach it over USB with `iproxy \(LProDevKit.port) \(LProDevKit.port)`; it answers while LinkedIn is in the foreground. Starting/stopping here takes effect immediately. The command console shows, live, what a connected viewer sends and what it gets back.")
            }

            Section("About") {
                LabeledContent("LinkedIn", value: "\(LinkedInVersion.short) (\(LinkedInVersion.build))")
                LabeledContent("LinkedIn Professional", value: GeneratedConfig.tweakVersion)
                LabeledContent("Build", value: GeneratedConfig.buildStamp)
                Link(destination: URL(string: "https://github.com/RobyRew/linkedin-pro-ios")!) {
                    LabeledContent("Source", value: "RobyRew/linkedin-pro-ios")
                }
            }

            Section {
                Text("LinkedIn Professional is an independent customization tweak. Not affiliated with LinkedIn.")
                    .font(.footnote).foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("LinkedIn Professional")
    }
}
