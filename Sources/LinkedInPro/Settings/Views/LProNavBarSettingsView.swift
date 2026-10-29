import SwiftUI

// Nav-bar settings. Writes UserDefaults.lproTabBar, read by NavBarCustomize:
// order, hidden tabs and added tabs all feed MainNavTabTypeFactory.mainNavTabsOrder.
struct LProNavBarSettingsView: View {
    @State private var options = UserDefaults.lproTabBar

    // Everything the bar can show: the user's order first, then any tab the hook
    // discovered that is not ordered yet. Hidden tabs stay listed so they can be
    // brought back where they were.
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

    // Extras that are not already in the bar. Read from stored state only: this
    // view must not touch LinkedIn's factory classes (constructing one traps).
    private var availableExtras: [TabCatalog.Extra] {
        TabCatalog.extras.filter { extra in
            if options.extraTabs.contains(extra.selector) { return false }
            let key = TabCatalog.normalized(extra.selector)
            if options.discoveredTabs.contains(where: { TabCatalog.normalized($0) == key }) {
                return false
            }
            if let known = options.extraTabNames[extra.selector],
               options.discoveredTabs.contains(known) { return false }
            return true
        }
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
                Text("Opts LinkedIn back into the iOS 26 design so the bottom bar becomes the floating Liquid Glass \u{201C}island\u{201D}. Experimental and app-wide - it can restyle other screens; if anything looks wrong, turn it off and relaunch.")
            }

            Section {
                if rows.isEmpty {
                    Text("Open LinkedIn's tabs once so they can be listed here, then come back.")
                        .font(.footnote).foregroundStyle(.secondary)
                } else {
                    ForEach(rows, id: \.self) { name in
                        tabRow(name)
                    }
                    .onMove(perform: move)
                }
            } header: {
                Text("Tabs")
            } footer: {
                Text("Drag to reorder. The eye hides a tab from the bar without losing its place here. At least one tab is always kept. Takes effect on relaunch.")
            }
            .environment(\.editMode, .constant(.active))

            if !availableExtras.isEmpty {
                Section {
                    ForEach(availableExtras, id: \.selector) { extra in
                        Button { add(extra) } label: {
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
                    Text("Add tabs")
                } footer: {
                    Text("Tabs LinkedIn can build but does not always show - Chat, Video, Games, Trends Hub. A tab the server already exposes is not listed here.")
                }
            }

            Section {
                Button("Reset tab customization", role: .destructive) { reset() }
                    .disabled(options.order.isEmpty && options.hiddenTabs.isEmpty && options.extraTabs.isEmpty)
            }
        }
        .navigationTitle("Navigation Bar")
        .onChange(of: options) { _, newValue in
            UserDefaults.lproTabBar = newValue
        }
    }

    @ViewBuilder
    private func tabRow(_ name: String) -> some View {
        HStack(spacing: 12) {
            icon(for: name)
                .frame(width: 24, height: 24)
                .opacity(options.hiddenTabs.contains(name) ? 0.35 : 1)
            Text(pretty(name))
                .foregroundStyle(options.hiddenTabs.contains(name) ? .secondary : .primary)
            Spacer()
            Button {
                toggleHidden(name)
            } label: {
                Image(systemName: options.hiddenTabs.contains(name) ? "eye.slash.fill" : "eye.fill")
                    .foregroundStyle(options.hiddenTabs.contains(name) ? Color.secondary : Color.accentColor)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(options.hiddenTabs.contains(name)
                                ? "Show \(pretty(name)) tab"
                                : "Hide \(pretty(name)) tab")
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

    private func toggleHidden(_ name: String) {
        if options.hiddenTabs.contains(name) {
            options.hiddenTabs.remove(name)
        } else {
            let visible = rows.filter { !options.hiddenTabs.contains($0) }
            guard visible.count > 1 else { return }  // never hide the last tab
            options.hiddenTabs.insert(name)
        }
    }

    private func add(_ extra: TabCatalog.Extra) {
        guard !options.extraTabs.contains(extra.selector) else { return }
        // The tab hook resolves the selector to its real tabName on the next
        // launch and appends it; until then it is listed as added.
        options.extraTabs.append(extra.selector)
    }

    private func move(from source: IndexSet, to destination: Int) {
        var list = rows
        list.move(fromOffsets: source, toOffset: destination)
        options.order = list
    }

    private func reset() {
        options.order = []
        options.hiddenTabs = []
        options.extraTabs = []
    }

    private func pretty(_ raw: String) -> String {
        if let extra = TabCatalog.extras.first(where: {
            $0.selector.lowercased() == raw.lowercased()
        }) { return extra.title }
        return raw.replacingOccurrences(of: "_", with: " ").capitalized
    }
}
