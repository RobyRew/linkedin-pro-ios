import Orion
import UIKit
import Foundation
import ObjectiveC.runtime
import LinkedInProC

// Phase 2, SDUI feed. The main feed is server-driven: each card is a generic SDUI
// component rendered by SDUI.Zen.ComponentCollectionViewDataSource into a
// ComponentCell, so the DashFeedUpdateBuilder data hook never sees a feed card
// (confirmed on device). Confirmed on device via Striker:
//   - the ad/reaction markers are NOT UILabel text; they are the accessibility
//     labels of SDUI.TextBlockView ("Promoted", "View Sponsored Content",
//     "<name> likes this", ...). An earlier UILabel-only scan saw nothing.
//   - the data source exposes only two @objc entry points we can hook:
//     collectionView:willDisplayCell:forItemAtIndexPath: and
//     collectionView:layout:sizeForItemAtIndexPath:. The feed uses explicit item
//     sizes (the flow-layout size delegate is implemented), so returning height 0
//     from the size method collapses a card with no leftover gap.
//
// Mechanism: in willDisplay we read the cell's accessibility labels, classify the
// card, and if the user hid that category we hide the cell and record its item so
// the size hook returns height 0 for it; the layout is invalidated only when the
// recorded set actually changes (no layout loop). Reused cells are restored when
// the card they now show is not a match. Detection is by delivered text, so it is
// locale-sensitive (English markers below; extend per locale).
//
// The data source is a Swift class not registered at launch, so the group is
// activated lazily the first time a FeedSDUIViewController appears.

// MARK: - lazy activation

struct SDUIFeedActivatorGroup: HookGroup {}

class SDUIFeedAppearHook: ClassHook<UIViewController> {
    typealias Group = SDUIFeedActivatorGroup

    func viewDidAppear(_ animated: Bool) {
        orig.viewDidAppear(animated)
        guard !SDUIFeedActivator.activated,
              NSStringFromClass(type(of: target)).contains("FeedSDUIViewController") else { return }
        SDUIFeedActivator.activated = true
        SDUIFeedActivator.activate(feedRoot: target.view)
    }
}

enum SDUIFeedActivator {
    static var activated = false

    static func activate(feedRoot: UIView?) {
        HookRegistry.shared.activate(SDUIFeedCellFilterGroup(), named: "sdui-cell-filter",
                                     requiring: ["_TtCO4SDUI3Zen33ComponentCollectionViewDataSource"])
        if LProDevKit.isEnabled, let root = feedRoot {
            let logPath = (NSTemporaryDirectory() as NSString).appendingPathComponent("linkedinpro.log")
            StrikerDumpView(Unmanaged.passUnretained(root).toOpaque(), logPath)
            LProLog.write("[feed] dumped FeedSDUIViewController subtree to the log")
        }
    }
}

// MARK: - cell filter (Zen data source)

struct SDUIFeedCellFilterGroup: HookGroup {}

class ZenComponentDataSourceHook: ClassHook<NSObject> {
    typealias Group = SDUIFeedCellFilterGroup
    static let targetName = "_TtCO4SDUI3Zen33ComponentCollectionViewDataSource"

    func collectionView(_ collectionView: UICollectionView,
                        willDisplay cell: UICollectionViewCell,
                        forItemAt indexPath: IndexPath) {
        orig.collectionView(collectionView, willDisplay: cell, forItemAt: indexPath)
        guard SDUIFeedFilter.isFeed(collectionView) else { return }

        if SDUIFeedFilter.hideReason(for: cell) != nil {
            cell.isHidden = true
            if SDUIFeedFilter.mark(collectionView, indexPath.item) {
                collectionView.collectionViewLayout.invalidateLayout()
            }
        } else {
            cell.isHidden = false
            if SDUIFeedFilter.unmark(collectionView, indexPath.item) {
                collectionView.collectionViewLayout.invalidateLayout()
            }
        }
    }

    func collectionView(_ collectionView: UICollectionView,
                        layout collectionViewLayout: UICollectionViewLayout,
                        sizeForItemAt indexPath: IndexPath) -> CGSize {
        let size = orig.collectionView(collectionView, layout: collectionViewLayout, sizeForItemAt: indexPath)
        if SDUIFeedFilter.isMarked(collectionView, indexPath.item) {
            return CGSize(width: size.width, height: 0)
        }
        return size
    }
}

enum SDUIFeedFilter {
    // Only act on the main feed, not every SDUI screen that shares this data
    // source class (jobs, the More tab, ...).
    static func isFeed(_ collectionView: UICollectionView) -> Bool {
        var responder: UIResponder? = collectionView
        var hops = 0
        while let r = responder, hops < 12 {
            if NSStringFromClass(type(of: r)).contains("FeedSDUIViewController") { return true }
            responder = r.next
            hops += 1
        }
        return false
    }

    // The category this card falls into, if the matching option is on; else nil.
    static func hideReason(for cell: UICollectionViewCell) -> String? {
        let opt = UserDefaults.lproFeedFilter
        guard opt.hideSponsored || opt.hidePromotions || opt.hidePremiumUpsell
            || opt.hideReactionSurfaced || opt.hideCommentSurfaced
        else { return nil }

        var budget = 400
        let labels = markers(in: cell.contentView, budget: &budget)

        if opt.hideSponsored, isSponsored(labels) { return "sponsored" }
        if opt.hidePremiumUpsell, isPremiumUpsell(labels) { return "premium-upsell" }
        if opt.hideReactionSurfaced, let r = reactionSurfaced(labels), opt.reactions.contains(r) {
            return "reaction:\(r.rawValue)"
        }
        if opt.hideCommentSurfaced, isCommentSurfaced(labels) { return "comment-surfaced" }
        if opt.hidePromotions, isPromotion(labels) { return "promotion" }
        return nil
    }

    // Accessibility labels + any UILabel text in the card. The SDUI markers live
    // in accessibility labels, not UILabel.text.
    private static func markers(in view: UIView, budget: inout Int) -> [String] {
        if budget <= 0 { return [] }
        budget -= 1
        var out: [String] = []
        if view.isAccessibilityElement, let a = view.accessibilityLabel, !a.isEmpty { out.append(a) }
        if let label = view as? UILabel, let t = label.text, !t.isEmpty { out.append(t) }
        for sub in view.subviews { out += markers(in: sub, budget: &budget) }
        return out
    }

    private static func isSponsored(_ labels: [String]) -> Bool {
        for raw in labels {
            let t = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if t == "promoted" || t == "sponsored" || t.hasPrefix("promoted ")
                || t.hasPrefix("sponsored ") || t.contains("sponsored content")
                || t.contains("promoted by") { return true }
        }
        return false
    }

    private static func isPremiumUpsell(_ labels: [String]) -> Bool {
        let joined = labels.joined(separator: "\n").lowercased()
        guard joined.contains("premium") else { return joined.contains("upsell") }
        return joined.contains("try") || joined.contains("free") || joined.contains("redeem")
            || joined.contains("month") || joined.contains("reactivate") || joined.contains("retry")
            || joined.contains("\u{20ac}") || joined.contains("$") || joined.contains("\u{00a3}")
    }

    // The social-proof header ("<name> likes this") is a short label.
    private static func reactionSurfaced(_ labels: [String]) -> LProReaction? {
        for raw in labels {
            let t = raw.lowercased()
            guard t.count < 90 else { continue }
            for reaction in LProReaction.allCases
            where reaction.headerPatterns.contains(where: { t.contains($0) }) {
                return reaction
            }
        }
        return nil
    }

    // Comment-surfaced social proof ("<name> commented on this").
    private static func isCommentSurfaced(_ labels: [String]) -> Bool {
        for raw in labels {
            let t = raw.lowercased()
            guard t.count < 90 else { continue }
            if t.contains("commented on this") || t.contains("replied to this") { return true }
        }
        return false
    }

    // Recommendation / suggestion chrome. Matched in short labels only (the promo
    // header), so a real post that merely contains a word is not caught.
    // NEEDS-DEVICE: confirm the exact markers of the promo cards that still slip
    // through (dump a live card's accessibility labels), then tighten this list.
    private static let promotionPhrases = [
        "people you may know", "add to your feed", "pages for you",
        "suggested for you", "recommended for you", "groups you may",
        "you might like", "suggested post", "suggested •", "recommended •",
        "from your network", "based on your", "trending on linkedin",
        "newsletters for you", "people also viewed", "jobs for you",
        "courses for you", "events for you",
    ]
    private static func isPromotion(_ labels: [String]) -> Bool {
        for raw in labels {
            let t = raw.lowercased()
            guard t.count < 90 else { continue }
            if promotionPhrases.contains(where: { t.contains($0) }) { return true }
        }
        return false
    }

    // MARK: marked-item store (per collection view)

    private static var markKey: UInt8 = 0
    private static func set(_ cv: UICollectionView) -> NSMutableIndexSet {
        if let s = objc_getAssociatedObject(cv, &markKey) as? NSMutableIndexSet { return s }
        let s = NSMutableIndexSet()
        objc_setAssociatedObject(cv, &markKey, s, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return s
    }
    // Returns true when the set changed (so the caller invalidates once).
    static func mark(_ cv: UICollectionView, _ item: Int) -> Bool {
        let s = set(cv)
        if s.contains(item) { return false }
        s.add(item)
        LProLog.write("[feed] hid item \(item)")
        return true
    }
    static func unmark(_ cv: UICollectionView, _ item: Int) -> Bool {
        let s = set(cv)
        if !s.contains(item) { return false }
        s.remove(item)
        return true
    }
    static func isMarked(_ cv: UICollectionView, _ item: Int) -> Bool { set(cv).contains(item) }
}
