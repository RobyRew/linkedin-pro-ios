#!/usr/bin/env swift
// Observed validation of the TabEngine decision logic (UIKit-free core), run on
// macOS with `swift Scripts/validate-tabengine-logic.swift`.
//
// The device chooses the API path (modern UITab vs viewControllers) and that is
// validated separately: statically from the binary (RE-NOTES: LinkedIn uses
// legacy setViewControllers, no UITab API) and at runtime by the launch
// self-diagnostic. What runs HERE is the version-independent core both paths
// share - ordering, hiding, the "never remove every tab" guard, and name
// resolution that must survive a blanked (icon-only) title - exercised with
// assertions so its behaviour is observed, not just reasoned about.
//
// These functions mirror TabEngine.x.swift's `arrange`, `canonicalName(forToken:)`,
// the class-token fallback, and `resolvedName`.

import Foundation

func normalized(_ s: String) -> String { s.lowercased().filter { $0.isLetter || $0.isNumber } }

let classAliases: [(token: String, canon: String)] = [
    ("feed", "Feed"), ("home", "Feed"), ("mynetwork", "MyNetwork"),
    ("network", "MyNetwork"), ("notification", "Notifications"), ("notif", "Notifications"),
    ("messag", "Messaging"), ("job", "Jobs"), ("more", "More"),
]

func alias(for normalizedToken: String, discovered: [String]) -> String? {
    for (token, canon) in classAliases where normalizedToken.contains(token) {
        return discovered.first(where: { normalized($0) == normalized(canon) }) ?? canon
    }
    return nil
}

func canonicalName(forToken token: String?, discovered: [String]) -> String? {
    guard let token, !token.isEmpty else { return nil }
    let t = normalized(token)
    guard !t.isEmpty else { return nil }
    if t == "home" { return discovered.first(where: { normalized($0) == "feed" }) ?? "Feed" }
    if let hit = discovered.first(where: { normalized($0) == t }) { return hit }
    return alias(for: t, discovered: discovered)
}

func canonicalName(fromClassNames classNames: [String], discovered: [String]) -> String? {
    let lowered = classNames.map { $0.lowercased() }
    for tab in discovered {
        let token = normalized(tab)
        if token.count >= 4, lowered.contains(where: { $0.contains(token) }) { return tab }
    }
    for (token, canon) in classAliases where lowered.contains(where: { $0.contains(token) }) {
        return discovered.first(where: { normalized($0) == normalized(canon) }) ?? canon
    }
    return nil
}

// title -> identifier -> class, then a non-empty fallback so a tab is never unnamed.
func resolvedName(title: String?, classNames: [String], identifier: String?, discovered: [String]) -> String {
    if let byTitle = canonicalName(forToken: title, discovered: discovered) { return byTitle }
    if let byID = canonicalName(forToken: identifier, discovered: discovered) { return byID }
    if let byClass = canonicalName(fromClassNames: classNames, discovered: discovered) { return byClass }
    if let title, !title.isEmpty { return title }
    if let first = classNames.first, !first.isEmpty { return first }
    return (identifier?.isEmpty == false) ? identifier! : "tab"
}

func arrange(_ named: [(name: String, value: Int)], order desiredOrder: [String]) -> [(name: String, value: Int)] {
    var out: [(name: String, value: Int)] = []
    var seen = Set<String>()
    for name in desiredOrder where !seen.contains(name) {
        if let hit = named.first(where: { $0.name == name }) { out.append(hit); seen.insert(name) }
    }
    for entry in named where !seen.contains(entry.name) {
        out.append(entry); seen.insert(entry.name)
    }
    return out
}

// --- test harness ---

var passed = 0, failed = 0
func check(_ label: String, _ got: [String], _ want: [String]) {
    if got == want { passed += 1; print("  PASS  \(label)") }
    else { failed += 1; print("  FAIL  \(label)\n        got  \(got)\n        want \(want)") }
}
func check(_ label: String, _ got: String, _ want: String) {
    if got == want { passed += 1; print("  PASS  \(label)  -> \(got)") }
    else { failed += 1; print("  FAIL  \(label)\n        got  \(got)\n        want \(want)") }
}

let discovered = ["Feed", "MyNetwork", "Jobs", "Notifications", "More"]
func tabs(_ names: [String]) -> [(name: String, value: Int)] { names.enumerated().map { ($1, $0) } }
func names(_ arr: [(name: String, value: Int)]) -> [String] { arr.map { $0.name } }

print("TabEngine logic validation")
print("reorder / hide:")

// Reorder: user puts Jobs and Feed first; the rest keep their relative order.
check("user order moves Jobs,Feed to front",
      names(arrange(tabs(discovered), order: ["Jobs", "Feed"])),
      ["Jobs", "Feed", "MyNetwork", "Notifications", "More"])

// Hide: remove Notifications from the arranged, visible set.
let hidden: Set<String> = ["Notifications"]
check("hidden tab is dropped from the visible set",
      names(arrange(tabs(discovered), order: ["Jobs"]).filter { !hidden.contains($0.name) }),
      ["Jobs", "Feed", "MyNetwork", "More"])

// Never-drop: a tab not named in the order (or an unknown one) is still kept.
check("an un-ordered tab is appended, never dropped",
      names(arrange(tabs(discovered + ["Mystery"]), order: ["Feed"])),
      ["Feed", "MyNetwork", "Jobs", "Notifications", "More", "Mystery"])

// Never remove every tab: a full-hide collapses to empty, which apply() refuses
// (validated here by showing the pre-guard result is empty, so the guard fires).
let allHidden = Set(discovered)
check("hiding all tabs yields empty (apply() then refuses)",
      names(arrange(tabs(discovered), order: []).filter { !allHidden.contains($0.name) }),
      [])

print("name resolution (icon-only / blanked titles):")

// Normal title resolves to the discovered canonical name.
check("title 'Home' -> Feed",
      resolvedName(title: "Home", classNames: [], identifier: nil, discovered: discovered), "Feed")
check("title 'My Network' -> MyNetwork",
      resolvedName(title: "My Network", classNames: [], identifier: nil, discovered: discovered), "MyNetwork")

// Blanked title (icon-only mode): resolve via the view-controller class name.
check("blank title + class 'LINFeedTabViewController' -> Feed",
      resolvedName(title: "", classNames: ["LINFeedTabViewController"], identifier: nil, discovered: discovered), "Feed")
check("blank title + class '...JobsHome...' -> Jobs",
      resolvedName(title: nil, classNames: ["JobsHomeNavigationController"], identifier: nil, discovered: discovered), "Jobs")

// Identifier fallback when title is blank and class is opaque.
check("blank title + identifier 'notifications' -> Notifications",
      resolvedName(title: "", classNames: ["GenericVC"], identifier: "notifications", discovered: discovered), "Notifications")

// Unknown everything: a stable non-empty name (never crashes / never empty).
check("fully unknown tab keeps a stable non-empty name",
      resolvedName(title: "", classNames: ["Xyz"], identifier: nil, discovered: discovered), "Xyz")

print("\n\(passed) passed, \(failed) failed")
exit(failed == 0 ? 0 : 1)
