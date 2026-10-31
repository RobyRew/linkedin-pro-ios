#!/usr/bin/env swift
// Observed validation of the feed-filter classification against the REAL
// accessibility markers captured from a live feed dump (Striker), run on macOS:
//   swift Scripts/validate-feedfilter-logic.swift
//
// This exercises the version-independent text logic SDUIFeedFilter.hideReason uses
// - the detectors and their order - with markers taken from an actual feed card
// (CloudForge AI, Luca Cruz) plus edge cases, so the classification is observed,
// not just reasoned about. The cell-collapse mechanism (height 0) is separate and
// already works on device for the existing categories.

import Foundation

struct Marker { let text: String; let minY: CGFloat }
let headerBand: CGFloat = 80

func lower(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }

func isSponsored(_ m: [Marker]) -> Bool {
    for x in m { let t = lower(x.text)
        if t == "promoted" || t == "sponsored" || t.hasPrefix("promoted ") || t.hasPrefix("sponsored ")
            || t.contains("sponsored content") || t.contains("promoted by") { return true } }
    return false
}
func isCommentSurfaced(_ h: [Marker]) -> Bool {
    for x in h { let t = x.text.lowercased(); guard t.count < 90 else { continue }
        if t.contains("commented") || t.contains("replied to") || t.contains("replied") { return true } }
    return false
}
func isRepostSurfaced(_ h: [Marker]) -> Bool {
    for x in h { let t = x.text.lowercased(); guard t.count < 90 else { continue }
        if t.contains("reposted this") || t.contains("reposted a post") || t.contains("reposted your post") { return true } }
    return false
}
func isFollowedBy(_ h: [Marker]) -> Bool {
    for x in h { let t = x.text.lowercased(); guard t.count < 90 else { continue }
        if t.contains("followed by") || t.contains("follows this") { return true } }
    return false
}
func isOutOfNetwork(_ h: [Marker]) -> Bool {
    for x in h { let t = lower(x.text); guard t.count < 16 else { continue }
        if t.contains("2nd") || t.contains("3rd") { return true } }
    return false
}
func isCompanyPost(_ h: [Marker]) -> Bool {
    for x in h { let t = x.text.lowercased()
        if t.hasPrefix("view company:") || t.hasPrefix("view page:") { return true } }
    return false
}

// Mirror of hideReason's enabled-filter order (reaction/upsell/promotion omitted
// here for brevity; they are unchanged and already validated).
func reason(_ markers: [Marker]) -> String? {
    let header = markers.filter { $0.minY < headerBand }
    if isSponsored(markers) { return "sponsored" }
    if isCommentSurfaced(header) { return "commented" }
    if isRepostSurfaced(header) { return "reposted" }
    if isFollowedBy(header) { return "followed-by" }
    if isCompanyPost(header) { return "company" }
    if isOutOfNetwork(header) { return "out-of-network" }
    return nil
}

var pass = 0, fail = 0
func check(_ label: String, _ got: String?, _ want: String?) {
    if got == want { pass += 1; print("  PASS  \(label)  -> \(got ?? "nil")") }
    else { fail += 1; print("  FAIL  \(label)\n        got  \(got ?? "nil")\n        want \(want ?? "nil")") }
}

print("feed-filter classification vs real captured markers")

// Real CloudForge AI card (company actor, no degree, no social proof).
check("CloudForge AI company post", reason([
    Marker(text: "View company: CloudForge AI", minY: 16),
    Marker(text: "CloudForge AI", minY: 16),
    Marker(text: "2d", minY: 33),
    Marker(text: "[English version below]\n\nDesde el 1 de octubre, Vercel ya no despliega", minY: 150),
]), "company")

// Real Luca Cruz card (3rd-degree person, not a connection).
check("Luca Cruz out-of-network (3rd+)", reason([
    Marker(text: "View Luca Cruz\u{2019}s profile", minY: 16),
    Marker(text: "Luca Cruz", minY: 16),
    Marker(text: " \u{2022} 3rd+", minY: 18),
    Marker(text: "Senior Software Entwickler:in bei Ayus Verda", minY: 30),
    Marker(text: "4d", minY: 42),
    Marker(text: "Picture a gestoria on a Tuesday morning.", minY: 150),
]), "out-of-network")

// A 1st-degree connection's own post must NOT be caught.
check("1st-degree connection (not caught)", reason([
    Marker(text: "View Jane Doe\u{2019}s profile", minY: 16),
    Marker(text: "Jane Doe", minY: 16),
    Marker(text: " \u{2022} 1st", minY: 18),
    Marker(text: "4d", minY: 42),
    Marker(text: "Shipped our new release today.", minY: 150),
]), nil)

// Body text mentioning "3rd" must NOT trigger out-of-network (body is below the
// header band and long).
check("body says '3rd quarter' (not caught)", reason([
    Marker(text: "View Jane Doe\u{2019}s profile", minY: 16),
    Marker(text: "Jane Doe", minY: 16),
    Marker(text: " \u{2022} 1st", minY: 18),
    Marker(text: "Our 3rd quarter results were strong across every region.", minY: 150),
]), nil)

// "Followed by" social proof.
check("Followed by X", reason([
    Marker(text: "Followed by Alex Smith", minY: 10),
    Marker(text: "Acme Corp", minY: 24),
    Marker(text: "1d", minY: 40),
]), "followed-by")

// Promoted ad still classified sponsored.
check("Promoted ad", reason([
    Marker(text: "Promoted", minY: 10),
    Marker(text: "Some Advertiser", minY: 24),
]), "sponsored")

// Comment-surfaced still wins over the relational filters (order).
check("comment-surfaced precedence", reason([
    Marker(text: "Bob commented on this", minY: 8),
    Marker(text: "View company: SomeCo", minY: 24),
    Marker(text: "SomeCo", minY: 24),
]), "commented")

print("\n\(pass) passed, \(fail) failed")
exit(fail == 0 ? 0 : 1)
