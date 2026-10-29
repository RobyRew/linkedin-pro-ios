import SwiftUI

// Nav-bar settings. Writes UserDefaults.lproTabBar; TabEngine applies the result
// to the live bar (and MainNavTabTypeFactory.mainNavTabsOrder does the same at
// launch for builds where the engine has not captured the controllers yet).
struct LProNavBarSettingsView: View {
    @State private var options = UserDefaults.lproTabBar

    // Every tab the bar knows about: user order first, then anything discovered
    // at launch. Hidden tabs stay here so they can be added back.
    private var rows: [String] {
        var seen = Set<String>()
        var out: [String] = []
        for name in options.order where !seen.contains(name) {
            seen.insert(name); out.append(name)
        }
        for name in options.discoveredTabs where !seen.contains(name) {
            seen.insert(name); out.append(name)
        }
        return out
    }

    private var activeTabs: [String] { rows.filter { !options.hiddenTabs.contains($0) } }
    private var availableTabs: [String] { rows.filter { options.hiddenTabs.contains($0) } }

    // Extras that exist as tab types but are not in the bar at all.
    private var availableExtras: [TabCatalog.Extra] {
        TabCatalog.extras.filter { extra in
            if options.extraTabs.contains(extra.selector) { return false }
            let key = TabCatalog.normalized(extra.selector)
            if rows.contains(where: { TabCatalog.normalized($0) == key }) { return false }
            if let known = options.extraTabNames[extra.selector], rows.contains(known) { return false }
            return true
        }
    }

    var body: some View {
        List {
            Section {
                Toggle("Hide tab labels", isOn: $options.hideLabels)
                Toggle("Dark tab bar only", isOn: $options.darkTabBar)
                Toggle("Long-press first tab opens settings", isOn: $options.longPressEntry)
            } header: {
                Text("Bottom bar")
            } footer: {
                Text("Dark applies to the bar alone, not the app. Icon-only drops the labels. Holding the first tab for half a second opens LinkedIn Professional.")
            }

            Section {
                if activeTabs.isEmpty {
                    Text("Open LinkedIn once so its tabs can be listed here.")
                        .font(.footnote).foregroundStyle(.secondary)
                } else {
                    ForEach(activeTabs, id: \.self) { name in
                        activeRow(name)
                    }
                    .onMove(perform: move)
                    .onDelete(perform: remove)
                }
            } header: {
                Text("Tab bar (\(activeTabs.count)/\(maxTabs))")
            } footer: {
                Text("Drag the three lines to reorder. Swipe a row to remove it from the bar - it moves to Available tabs. At least one tab is always kept.")
            }
            .environment(\.editMode, .constant(.active))

            Section {
                Picker("Open on launch", selection: $options.defaultTab) {
                    Text("LinkedIn's choice").tag("")
                    ForEach(activeTabs, id: \.self) { name in
                        Text(pretty(name)).tag(name)
                    }
                }
            } header: {
                Text("Launch")
            } footer: {
                Text("Only tabs in the bar can be chosen. If the chosen tab is removed from the bar, LinkedIn's own choice is used again.")
            }

            if !availableTabs.isEmpty {
                Section {
                    ForEach(availableTabs, id: \.self) { name in
                        availableRow(name)
                    }
                } header: {
                    Text("Available tabs")
                } footer: {
                    Text("Removed from the bar. Tap + to put one back.")
                }
            }

            if !availableExtras.isEmpty {
                Section {
                    ForEach(availableExtras, id: \.selector) { extra in
                        Button { addExtra(extra) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: extra.symbol)
                                    .frame(width: 24)
                                    .foregroundStyle(.tint)
                                Text(extra.title).foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "plus.circle.fill").foregroundStyle(.tint)
                            }
                        }
                    }
                } header: {
                    Text("Other tab types")
                } footer: {
                    Text("This LinkedIn build exposes five tab types; chat and video are not among them.")
                }
            }

            Section {
                Button("Apply now") {
                    persist()
                    let applied = TabEngine.apply()
                    LProLog.write("[navbar] manual apply -> \(applied ? "rebuilt" : "no change")")
                }
                Button("Reset tab customization", role: .destructive) { reset() }
                    .disabled(options.order.isEmpty && options.hiddenTabs.isEmpty && options.extraTabs.isEmpty)
            }
        }
        .navigationTitle("Navigation Bar")
        .onChange(of: options) { _, newValue in
            // A hidden tab cannot be the launch tab.
            if !newValue.defaultTab.isEmpty, !newValue.hiddenTabs.isEmpty,
               newValue.hiddenTabs.contains(newValue.defaultTab) {
                options.defaultTab = ""
            }
            persist()
        }
    }

    private let maxTabs = 8

    @ViewBuilder
    private func activeRow(_ name: String) -> some View {
        HStack(spacing: 12) {
            icon(for: name).frame(width: 24, height: 24)
            Text(pretty(name))
            Spacer()
            // Swipe the row or tap this to move it to Available tabs.
            Button { removeOne(name) } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(pretty(name)) from the tab bar")
        }
    }

    @ViewBuilder
    private func availableRow(_ name: String) -> some View {
        HStack(spacing: 12) {
            icon(for: name).frame(width: 24, height: 24).opacity(0.5)
            Text(pretty(name)).foregroundStyle(.secondary)
            Spacer()
            Button { restore(name) } label: {
                Image(systemName: "plus.circle.fill").foregroundStyle(.tint)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add \(pretty(name)) to the tab bar")
        }
    }

    @ViewBuilder
    private func icon(for name: String) -> some View {
        if let image = TabIconStore.image(for: name) {
            Image(uiImage: image).renderingMode(.template)
        } else {
            Image(systemName: TabCatalog.symbol(forTabNamed: name))
        }
    }

    // Swipe-to-delete: remove from the bar, keep it under Available tabs.
    private func remove(at offsets: IndexSet) {
        let active = activeTabs
        guard active.count - offsets.count >= 1 else { return }  // never zero tabs
        for index in offsets where index < active.count {
            let name = active[index]
            options.hiddenTabs.insert(name)
            if options.defaultTab == name { options.defaultTab = "" }
        }
        options.order = activeTabs + availableTabs
    }

    private func removeOne(_ name: String) {
        guard activeTabs.count > 1 else { return }
        options.hiddenTabs.insert(name)
        if options.defaultTab == name { options.defaultTab = "" }
        options.order = activeTabs + availableTabs
    }

    private func restore(_ name: String) {
        guard activeTabs.count < maxTabs else { return }
        options.hiddenTabs.remove(name)
        var list = activeTabs
        if !list.contains(name) { list.append(name) }
        options.order = list + availableTabs.filter { $0 != name }
    }

    private func move(from source: IndexSet, to destination: Int) {
        var list = activeTabs
        list.move(fromOffsets: source, toOffset: destination)
        options.order = list + availableTabs
    }

    private func addExtra(_ extra: TabCatalog.Extra) {
        guard !options.extraTabs.contains(extra.selector) else { return }
        options.extraTabs.append(extra.selector)
    }

    private func reset() {
        options.order = []
        options.hiddenTabs = []
        options.extraTabs = []
        options.defaultTab = ""
    }

    private func persist() {
        UserDefaults.lproTabBar = options
        TabEngine.applyAppearance()
        _ = TabEngine.apply()
    }

    private func pretty(_ raw: String) -> String {
        if let extra = TabCatalog.extras.first(where: {
            $0.selector.lowercased() == raw.lowercased()
        }) { return extra.title }
        return raw.replacingOccurrences(of: "_", with: " ").capitalized
    }
}
