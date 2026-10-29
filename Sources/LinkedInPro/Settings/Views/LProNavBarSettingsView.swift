import SwiftUI

// Nav-bar settings. Writes UserDefaults.lproTabBar, read by NavBarCustomize.
struct LProNavBarSettingsView: View {
    @State private var options = UserDefaults.lproTabBar

    var body: some View {
        List {
            Section {
                Toggle("Hide tab labels", isOn: $options.hideLabels)
            } header: {
                Text("Bottom bar")
            } footer: {
                Text("Icon-only tabs. Takes effect as the bar rebuilds (reopen the app if a tab keeps its label). Reorder and hide-tab are coming.")
            }
        }
        .navigationTitle("Navigation Bar")
        .onChange(of: options) { _, newValue in
            UserDefaults.lproTabBar = newValue
        }
    }
}
