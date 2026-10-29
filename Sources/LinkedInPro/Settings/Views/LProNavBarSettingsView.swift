import SwiftUI

// Nav-bar settings. Writes UserDefaults.lproTabBar, read by NavBarCustomize.
struct LProNavBarSettingsView: View {
    @State private var options = UserDefaults.lproTabBar

    // The list to show/reorder: the user's order if set, else the tabs the
    // reorder hook discovered at runtime.
    private var tabs: [String] {
        options.order.isEmpty ? options.discoveredTabs : options.order
    }

    var body: some View {
        List {
            Section {
                Toggle("Hide tab labels", isOn: $options.hideLabels)
            } header: {
                Text("Bottom bar")
            } footer: {
                Text("Icon-only tabs. Takes effect as the bar rebuilds (reopen the app if a tab keeps its label).")
            }

            Section {
                Toggle("iOS 26 floating glass tabs", isOn: $options.iOS26GlassTabs)
            } header: {
                Text("iOS 26 design")
            } footer: {
                Text("Opts LinkedIn back into the iOS 26 design so the bottom bar becomes the floating Liquid Glass \u{201C}island\u{201D}. Experimental and app-wide - it can restyle other screens; if anything looks wrong, turn it off and relaunch. Needs a relaunch to apply.")
            }

            if tabs.isEmpty {
                Section("Tab order") {
                    Text("Open LinkedIn's tabs once so they can be listed here, then come back.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            } else {
                Section {
                    ForEach(tabs, id: \.self) { Text(pretty($0)) }
                        .onMove(perform: move)
                } header: {
                    Text("Tab order")
                } footer: {
                    Text("Drag to reorder the bottom tabs. Reorder only - tabs are never removed. Takes effect on relaunch.")
                }
                .environment(\.editMode, .constant(.active))
            }
        }
        .navigationTitle("Navigation Bar")
        .onChange(of: options) { _, newValue in
            UserDefaults.lproTabBar = newValue
        }
    }

    private func move(from source: IndexSet, to destination: Int) {
        var list = tabs
        list.move(fromOffsets: source, toOffset: destination)
        options.order = list
    }

    private func pretty(_ raw: String) -> String {
        raw.replacingOccurrences(of: "_", with: " ").capitalized
    }
}
