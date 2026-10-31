import Orion
import UIKit
import Foundation
import ObjectiveC.runtime
import LinkedInProC

// Phase 2, SDUI feed. The main feed is server-driven: each card is a generic SDUI
// component rendered by SDUI.Zen.ComponentCollectionViewDataSource into a
// ComponentCell, so the DashFeedUpdateBuilder data hook never sees a feed card
// (confirmed on device). Confirmed on device via Striker:
//   - the ad/reaction/comment markers are NOT UILabel text; they are the
//     accessibility labels of SDUI.TextBlockView ("Promoted", "View Sponsored
//     Content", "<name> finds this funny", ...). An earlier UILabel-only scan saw
//     nothing.
//   - the data source exposes only two @objc entry points we can hook:
//     collectionView:willDisplayCell:forItemAtIndexPath: and
//     collectionView:layout:sizeForItemAtIndexPath:. The feed uses explicit item
//     sizes (the flow-layout size delegate is implemented), so returning height 0
//     from the size method collapses a card with no leftover gap.
//
// Mechanism: in willDisplay we read the cell's labels with their position, classify
// the card, and if the user hid that category we hide the cell and record its item
// so the size hook returns height 0 for it; the layout is invalidated only when the
// recorded set actually changes (no layout loop). Reused cells are restored when
// the card they now show is not a match. Detection is by delivered text, so it is
// locale-sensitive (English markers below; extend per locale).
//
// "Surfaced by a reaction/comment" is decided only from labels in the CARD HEADER
// band: the social-proof line ("X finds this funny") sits above the author row,
// while post bodies are also accessibility labels and would otherwise match.
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
        SDUICellFilterInstaller.install()
        if LProDevKit.isEnabled, let root = feedRoot {
            let logPath = (NSTemporaryDirectory() as NSString).appendingPathComponent("linkedinpro.log")
            StrikerDumpView(Unmanaged.passUnretained(root).toOpaque(), logPath)
            LProLog.write("[feed] dumped FeedSDUIViewController subtree to the log")
        }
    }
}

// MARK: - cell filter (Zen data source)

// Hooked with the runtime directly, not Orion. Orion derives a selector from the
// Swift method name ("collectionView:willDisplay:forItemAt:") while the class
// implements the UIKit one ("collectionView:willDisplayCell:forItemAtIndexPath:"),
// so its ClassHook failed to bind:
//   [orion] Failed to hook method -[ComponentCollectionViewDataSource
//           collectionView:willDisplay:forItemAt:] (Could not hook method)
// Selectors confirmed live with `methods _TtCO4SDUI3Zen33ComponentCollectionViewDataSource`.
enum SDUICellFilterInstaller {
    private static var installed = false

    static func install() {
        guard !installed else { return }
        let name = "_TtCO4SDUI3Zen33ComponentCollectionViewDataSource"
        guard let cls = NSClassFromString(name) else { return }
        installed = true

        hookWillDisplay(cls)
        hookSize(cls)
        LProLog.write("[feed] installed cell filter on \(name)")
    }

    private static func hookWillDisplay(_ cls: AnyClass) {
        let sel = NSSelectorFromString("collectionView:willDisplayCell:forItemAtIndexPath:")
        guard let method = class_getInstanceMethod(cls, sel) else { return }
        let types = method_getTypeEncoding(method)
        typealias Fn = @convention(c) (AnyObject, Selector, UICollectionView,
                                       UICollectionViewCell, NSIndexPath) -> Void
        let orig = unsafeBitCast(method_getImplementation(method), to: Fn.self)

        let block: @convention(block) (AnyObject, UICollectionView, UICollectionViewCell,
                                       NSIndexPath) -> Void = { obj, cv, cell, ip in
            orig(obj, sel, cv, cell, ip)
            guard SDUIFeedFilter.isFeed(cv) else { return }
            let indexPath = ip as IndexPath

            if let reason = SDUIFeedFilter.hideReason(for: cell) {
                cell.isHidden = true
                if SDUIFeedFilter.mark(cv, indexPath.item) {
                    SDUIFeedStats.note(reason)
                    LProLog.write("[feed] hid item \(indexPath.item) (\(reason))")
                    SDUIFeedFilter.scheduleInvalidation(cv, indexPath)
                }
            } else {
                cell.isHidden = false
                if SDUIFeedFilter.unmark(cv, indexPath.item) {
                    SDUIFeedFilter.scheduleInvalidation(cv, indexPath)
                }
            }
        }
        replace(cls, sel, method, imp_implementationWithBlock(block), types)
    }

    private static func hookSize(_ cls: AnyClass) {
        let sel = NSSelectorFromString("collectionView:layout:sizeForItemAtIndexPath:")
        guard let method = class_getInstanceMethod(cls, sel) else { return }
        let types = method_getTypeEncoding(method)
        typealias Fn = @convention(c) (AnyObject, Selector, UICollectionView,
                                       UICollectionViewLayout, NSIndexPath) -> CGSize
        let orig = unsafeBitCast(method_getImplementation(method), to: Fn.self)

        let block: @convention(block) (AnyObject, UICollectionView, UICollectionViewLayout,
                                       NSIndexPath) -> CGSize = { obj, cv, layout, ip in
            let size = orig(obj, sel, cv, layout, ip)
            if SDUIFeedFilter.isMarked(cv, (ip as IndexPath).item) {
                return CGSize(width: size.width, height: 0)
            }
            return size
        }
        replace(cls, sel, method, imp_implementationWithBlock(block), types)
    }

    // Add an override on the class when the implementation is inherited; else
    // replace in place. Called once per class, so no re-entrancy.
    private static func replace(_ cls: AnyClass, _ sel: Selector, _ method: Method,
                                _ imp: IMP, _ types: UnsafePointer<CChar>?) {
        if class_addMethod(cls, sel, imp, types) { return }
        method_setImplementation(method, imp)
    }
}

// How many cards this session hid, by reason. Shown in the feed settings so a
// filter that never fires (wrong locale, changed marker) is visible immediately.
enum SDUIFeedStats {
    private(set) static var counts: [String: Int] = [:]

    static func note(_ reason: String) {
        counts[reason, default: 0] += 1
    }

    static var summary: [(reason: String, count: Int)] {
        counts.sorted { $0.value > $1.value }.map { (reason: $0.key, count: $0.value) }
    }

    static func reset() { counts = [:] }
}

enum SDUIFeedFilter {
    // Only act on the main feed, not every SDUI screen that shares this data
    // source class (jobs, the More tab, ...). The answer is stable for a given
    // collection view, so it is cached per instance: the responder-chain walk ran
    // on every willDisplay before, once per cell.
    private static var isFeedKey: UInt8 = 0
    static func isFeed(_ collectionView: UICollectionView) -> Bool {
        if let cached = objc_getAssociatedObject(collectionView, &isFeedKey) as? NSNumber {
            return cached.boolValue
        }
        var responder: UIResponder? = collectionView
        var hops = 0
        var result = false
        while let r = responder, hops < 24 {
            if NSStringFromClass(type(of: r)).contains("FeedSDUIViewController") { result = true; break }
            responder = r.next
            hops += 1
        }
        objc_setAssociatedObject(collectionView, &isFeedKey, NSNumber(value: result),
                                 .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return result
    }

    // Coalesced, TARGETED layout invalidation. A hide/unhide changes one item's
    // height (to 0, or back), so only that item needs re-laying out. The old code
    // called `collectionViewLayout.invalidateLayout()` synchronously inside
    // willDisplay: a full invalidation re-runs sizeForItem for every item AND
    // re-displays (so re-classifies) every visible cell, and each newly matched
    // card triggered another full pass - the stall under heavy filtering
    // (out-of-network / company hide a large share of cards). Instead, record the
    // changed item and, once per run-loop turn, invalidate just those items with a
    // flow-layout context. Scheduling on the next turn also avoids re-entering
    // layout from within a layout/display pass.
    private static var pendingKey: UInt8 = 0
    private static var flushScheduledKey: UInt8 = 0

    private static func pendingItems(_ cv: UICollectionView) -> NSMutableSet {
        if let s = objc_getAssociatedObject(cv, &pendingKey) as? NSMutableSet { return s }
        let s = NSMutableSet()
        objc_setAssociatedObject(cv, &pendingKey, s, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return s
    }

    static func scheduleInvalidation(_ cv: UICollectionView, _ indexPath: IndexPath) {
        pendingItems(cv).add(indexPath)
        guard objc_getAssociatedObject(cv, &flushScheduledKey) == nil else { return }
        objc_setAssociatedObject(cv, &flushScheduledKey, true, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        DispatchQueue.main.async { [weak cv] in
            guard let cv else { return }
            objc_setAssociatedObject(cv, &flushScheduledKey, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            let set = pendingItems(cv)
            let paths = set.allObjects.compactMap { $0 as? IndexPath }
            set.removeAllObjects()
            guard !paths.isEmpty else { return }
            if let flow = cv.collectionViewLayout as? UICollectionViewFlowLayout {
                let ctx = UICollectionViewFlowLayoutInvalidationContext()
                ctx.invalidateItems(at: paths)
                flow.invalidateLayout(with: ctx)
            } else {
                cv.collectionViewLayout.invalidateLayout()
            }
        }
    }

    private struct Marker {
        let text: String
        let minY: CGFloat   // in cell coordinates
    }

    // Labels whose vertical position is inside the card header (social proof
    // line, author row) rather than the post body.
    private static let headerBand: CGFloat = 80

    // The category this card falls into, if the matching option is on; else nil.
    static func hideReason(for cell: UICollectionViewCell) -> String? {
        let opt = LProFeedFilterCache.current
        guard opt.hideSponsored || opt.hidePromotions || opt.hidePremiumUpsell
            || opt.hideReactionSurfaced || opt.hideCommentSurfaced || opt.hideRepostSurfaced
            || opt.hideFollowedBy || opt.hideOutOfNetwork || opt.hideCompanyPosts
        else { return nil }

        var budget = 500
        let markers = collect(in: cell, budget: &budget)
        let header = markers.filter { $0.minY < headerBand }

        if opt.hideSponsored, isSponsored(markers) { return "sponsored" }
        if opt.hidePremiumUpsell, isPremiumUpsell(markers) { return "premium-upsell" }
        if opt.hideReactionSurfaced, let r = reactionSurfaced(header), opt.reactions.contains(r) {
            return "reaction-\(r.rawValue)"
        }
        if opt.hideCommentSurfaced, isCommentSurfaced(header) { return "commented" }
        if opt.hideRepostSurfaced, isRepostSurfaced(header) { return "reposted" }
        if opt.hideFollowedBy, isFollowedBy(header) { return "followed-by" }
        if opt.hidePromotions, isPromotion(markers) { return "promotion" }
        // Relational filters last: they are the broadest, so a card that also
        // matched a more specific reason above is attributed to that reason.
        if opt.hideCompanyPosts, isCompanyPost(header) { return "company" }
        if opt.hideOutOfNetwork, isOutOfNetwork(header) { return "out-of-network" }
        return nil
    }

    // "Followed by X" / "X follows this" social proof in the header band.
    private static func isFollowedBy(_ header: [Marker]) -> Bool {
        for marker in header {
            let t = marker.text.lowercased()
            guard t.count < 90 else { continue }
            if t.contains("followed by") || t.contains("follows this") { return true }
        }
        return false
    }

    // Author is outside your network: the header carries a 2nd/3rd-degree chip
    // (e.g. " • 3rd+"). 1st-degree connections and your own posts never show one.
    private static func isOutOfNetwork(_ header: [Marker]) -> Bool {
        for marker in header {
            let t = marker.text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            guard t.count < 16 else { continue }   // the degree chip is tiny
            if t.contains("2nd") || t.contains("3rd") { return true }
        }
        return false
    }

    // Company / Page post: the actor avatar's accessibility label is
    // "View company: <name>" (confirmed live). People's actors say "View <name>'s
    // profile" instead, so this does not catch member posts.
    private static func isCompanyPost(_ header: [Marker]) -> Bool {
        for marker in header {
            let t = marker.text.lowercased()
            if t.hasPrefix("view company:") || t.hasPrefix("view page:") { return true }
        }
        return false
    }

    // Accessibility labels + any UILabel text, each with its y in cell space. The
    // SDUI markers live in accessibility labels, not UILabel.text.
    private static func collect(in cell: UICollectionViewCell, budget: inout Int) -> [Marker] {
        var out: [Marker] = []
        func walk(_ view: UIView, _ depth: Int) {
            guard budget > 0, depth < 40 else { return }
            budget -= 1
            var texts: [String] = []
            if view.isAccessibilityElement, let a = view.accessibilityLabel, !a.isEmpty {
                texts.append(a)
            }
            if let label = view as? UILabel, let t = label.text, !t.isEmpty, !texts.contains(t) {
                texts.append(t)
            }
            if !texts.isEmpty {
                // Y is only consulted for short header markers (every header check
                // guards text.count < 90). A long body label can never be a header
                // marker, so skip its coordinate conversion - convert() is the per
                // node cost of this walk.
                let y: CGFloat = texts.contains(where: { $0.count < 90 })
                    ? view.convert(view.bounds, to: cell).minY
                    : .greatestFiniteMagnitude
                for t in texts { out.append(Marker(text: t, minY: y)) }
            }
            for sub in view.subviews { walk(sub, depth + 1) }
        }
        walk(cell.contentView, 0)
        return out
    }

    private static func isSponsored(_ markers: [Marker]) -> Bool {
        for marker in markers {
            let t = marker.text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if t == "promoted" || t == "sponsored" || t.hasPrefix("promoted ")
                || t.hasPrefix("sponsored ") || t.contains("sponsored content")
                || t.contains("promoted by") { return true }
        }
        return false
    }

    private static func isPremiumUpsell(_ markers: [Marker]) -> Bool {
        let joined = markers.map { $0.text }.joined(separator: "\n").lowercased()
        guard joined.contains("premium") else { return joined.contains("upsell") }
        return joined.contains("try") || joined.contains("free") || joined.contains("redeem")
            || joined.contains("month") || joined.contains("reactivate") || joined.contains("retry")
            || joined.contains("\u{20ac}") || joined.contains("$") || joined.contains("\u{00a3}")
    }

    // The social-proof header ("<name> likes this") is a short label in the
    // header band.
    private static func reactionSurfaced(_ header: [Marker]) -> LProReaction? {
        for marker in header {
            let t = marker.text.lowercased()
            guard t.count < 90 else { continue }
            for reaction in LProReaction.allCases
            where reaction.headerPatterns.contains(where: { t.contains($0) }) {
                return reaction
            }
        }
        return nil
    }

    // Comment-surfaced social proof ("<name> commented on this" / "... and 3
    // others commented on this"), same header band.
    private static func isCommentSurfaced(_ header: [Marker]) -> Bool {
        for marker in header {
            let t = marker.text.lowercased()
            guard t.count < 90 else { continue }
            // LinkedIn uses several forms ("X commented on this", "X and 3 others
            // commented on this", "X commented on a post", "X replied to this"),
            // so any comment word in the header band counts.
            if t.contains("commented") || t.contains("replied to")
                || t.contains("replied") { return true }
        }
        return false
    }

    // Reposts ("<name> reposted this").
    private static func isRepostSurfaced(_ header: [Marker]) -> Bool {
        for marker in header {
            let t = marker.text.lowercased()
            guard t.count < 90 else { continue }
            if t.contains("reposted this") || t.contains("reposted a post")
                || t.contains("reposted your post") { return true }
        }
        return false
    }

    // Recommendation / suggestion chrome. Unambiguous phrases match anywhere in
    // the card; the generic ones ("suggested", "recommended") only match in the
    // header band, so a post that merely contains the word is not caught.
    // NEEDS-DEVICE: confirm the exact markers of promo cards that still slip
    // through (dump a live card's accessibility labels), then tighten this list.
    private static let promoChromePhrases = [
        "people you may know", "people you might know", "add to your feed",
        "pages for you", "suggested for you", "recommended for you",
        "groups you may", "you might like", "suggested post", "recommended post",
        "from your network", "based on your activity", "based on your profile",
        "trending on linkedin", "trending now", "newsletters for you",
        "people also viewed", "jobs for you", "courses for you", "events for you",
        "top picks for you", "popular on linkedin", "because you follow",
        "because you\u{2019}re following", "because you're following",
        "similar pages", "similar to pages you follow", "follow these pages",
        "invite your connections", "catch up on", "linkedin news",
        "continue reading", "recommended reading", "more from your network",
        "puzzles", "daily puzzle", "games you may", "your daily",
    ]

    private static let promoExactHeaders = ["suggested", "recommended", "suggested for you"]

    private static func isPromotion(_ markers: [Marker]) -> Bool {
        for marker in markers {
            let t = marker.text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard t.count < 80 else { continue }
            if promoExactHeaders.contains(t) { return true }
            if promoChromePhrases.contains(where: { t.contains($0) }) { return true }
            // Generic "suggested"/"recommended"/"trending" only at the header.
            if marker.minY < headerBand,
               ["suggested", "recommended", "trending", "for you"].contains(where: { t.hasPrefix($0) }) {
                return true
            }
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
