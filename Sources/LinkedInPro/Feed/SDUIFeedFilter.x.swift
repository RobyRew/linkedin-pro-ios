import Orion
import UIKit
import Foundation
import LinkedInProC

// Phase 2, SDUI feed. LinkedIn's feed is server-driven: each card is a generic
// SDUI ComponentViewModel rendered by SDUI.ComponentCollectionViewAdapter, so
// the DashFeedUpdateBuilder data hook never sees a feed card (confirmed on
// device: `[feed] hid` stayed 0 while scrolling). Two mechanisms here, split by
// what each can do safely:
//
//   1. SHIPPING FILTER - cell level (always on when a clean-up option is on).
//      When the adapter dequeues a feed cell we walk its view tree for the
//      server-delivered markers - "Promoted"/"Sponsored" for ads, Premium
//      upsell text, and the fixed suggestion/recommendation chrome phrases - and
//      collapse the cell to zero height (NOX cells self-size, so a 0-height
//      contentView constraint removes the gap). The marker is delivered text,
//      not a compiled constant, so it is matched at runtime and is
//      locale-sensitive (English phrases below; extend per locale from the log).
//      Reused cells are restored when the model they now show is not a match.
//
//   2. DEVKIT INSTRUMENTATION - data level (DevKit only, log-only). At
//      NOXAdapter.setSections: we log each model's SDUI metadata (typeId /
//      semanticId / protoMessageName / observabilityViewName). That metadata is
//      the per-card ad marker a clean data-layer drop would key on; it is not a
//      flag we can read blind, so we do NOT mutate the section array here - a
//      wrong drop breaks the feed's data source. Capturing the real marker on
//      device is the input to the data-layer drop in a later build.
//
// The adapter is a Swift class not registered at launch, so both groups are
// activated lazily the first time a FeedSDUIViewController appears (see
// SDUIFeedActivator), by which point the classes exist and Orion can bind them.

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
        HookRegistry.shared.activate(SDUICellFilterGroup(), named: "sdui-cell-filter",
                                     requiring: ["_TtC4SDUI30ComponentCollectionViewAdapter"])
        if LProDevKit.isEnabled {
            HookRegistry.shared.activate(SDUIFeedInstrumentGroup(), named: "sdui-feed-instrument",
                                         requiring: ["NOXAdapter"])
            // Capture the feed subtree once, so the SDUI card view structure can
            // be read back over USB without a live session.
            let logPath = (NSTemporaryDirectory() as NSString).appendingPathComponent("linkedinpro.log")
            if let root = feedRoot {
                StrikerDumpView(Unmanaged.passUnretained(root).toOpaque(), logPath)
                LProLog.write("[feed] dumped FeedSDUIViewController subtree to the log")
            }
        }
    }
}

// MARK: - cell-level collapse (shipping filter)

struct SDUICellFilterGroup: HookGroup {}

class SDUIComponentCellHook: ClassHook<NSObject> {
    typealias Group = SDUICellFilterGroup
    static let targetName = "_TtC4SDUI30ComponentCollectionViewAdapter"

    func collectionView(_ collectionView: UICollectionView,
                        cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = orig.collectionView(collectionView, cellForItemAt: indexPath)
        SDUIFeedCellFilter.apply(to: cell)
        return cell
    }
}

enum SDUIFeedCellFilter {
    private static let collapseID = "LProFeedCollapse"

    static func apply(to cell: UICollectionViewCell) {
        let opt = UserDefaults.lproFeedFilter
        guard opt.hideSponsored || opt.hidePromotions || opt.hidePremiumUpsell else {
            restore(cell); return
        }

        let texts = labelTexts(in: cell.contentView)
        let joined = texts.joined(separator: "\n").lowercased()

        var why: String?
        if opt.hideSponsored, isSponsored(texts) {
            why = "sponsored"
        } else if opt.hidePremiumUpsell, isPremiumUpsell(joined) {
            why = "premium-upsell"
        } else if opt.hidePromotions, isPromotion(joined) {
            why = "promotion"
        }

        if let why = why { collapse(cell, why) } else { restore(cell) }
    }

    // A standalone "Promoted"/"Sponsored" actor subtitle marks an ad. Match a
    // short label equal to (or starting with) the marker, so a post whose body
    // merely contains the word is not caught.
    private static func isSponsored(_ texts: [String]) -> Bool {
        for raw in texts {
            let t = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if t.count <= 16 && (t == "promoted" || t == "sponsored"
                || t.hasPrefix("promoted ") || t.hasPrefix("sponsored ")) { return true }
        }
        return false
    }

    private static func isPremiumUpsell(_ joined: String) -> Bool {
        guard joined.contains("premium") else { return joined.contains("upsell") }
        return joined.contains("try") || joined.contains("free") || joined.contains("redeem")
            || joined.contains("month") || joined.contains("reactivate") || joined.contains("retry")
            || joined.contains("\u{20ac}") || joined.contains("$") || joined.contains("\u{00a3}")
    }

    // Only the fixed recommendation/suggestion chrome phrases - not loose words
    // like "trending" or "recommended" that a real post may use in its body.
    private static let promotionPhrases = [
        "people you may know", "add to your feed", "pages for you",
        "suggested for you", "recommended for you", "groups you may",
    ]
    private static func isPromotion(_ joined: String) -> Bool {
        promotionPhrases.contains { joined.contains($0) }
    }

    private static func labelTexts(in root: UIView, depth: Int = 0, budget: inout Int) -> [String] {
        if budget <= 0 || depth > 12 { return [] }
        budget -= 1
        var out: [String] = []
        if let label = root as? UILabel, let t = label.text, !t.isEmpty { out.append(t) }
        else if let field = root as? UITextField, let t = field.text, !t.isEmpty { out.append(t) }
        else if let tv = root as? UITextView, !tv.text.isEmpty { out.append(tv.text) }
        for sub in root.subviews { out += labelTexts(in: sub, depth: depth + 1, budget: &budget) }
        return out
    }
    private static func labelTexts(in root: UIView) -> [String] {
        var budget = 400
        return labelTexts(in: root, budget: &budget)
    }

    private static func collapse(_ cell: UICollectionViewCell, _ why: String) {
        let content = cell.contentView
        if content.constraints.contains(where: { $0.identifier == collapseID }) { return }
        content.clipsToBounds = true
        for sub in content.subviews { sub.isHidden = true }
        let c = content.heightAnchor.constraint(equalToConstant: 0)
        c.priority = UILayoutPriority(999)  // self-sizing wins; avoids an unsatisfiable-constraint storm
        c.identifier = collapseID
        c.isActive = true
        cell.isHidden = true
        LProLog.write("[feed] collapsed \(why)")
    }

    private static func restore(_ cell: UICollectionViewCell) {
        let content = cell.contentView
        guard let c = content.constraints.first(where: { $0.identifier == collapseID }) else { return }
        c.isActive = false
        for sub in content.subviews { sub.isHidden = false }
        cell.isHidden = false
    }
}

// MARK: - data-level instrumentation (DevKit only, log-only)

struct SDUIFeedInstrumentGroup: HookGroup {}

class NOXAdapterSetSectionsHook: ClassHook<NSObject> {
    typealias Group = SDUIFeedInstrumentGroup
    static let targetName = "NOXAdapter"

    func setSections(_ sections: NSArray?) {
        orig.setSections(sections)
        guard LProDevKit.isEnabled else { return }
        SDUIFeedInstrument.log(adapter: target, sections: sections)
    }
}

enum SDUIFeedInstrument {
    // Keys that carry the SDUI card type marker we would key a data-layer drop
    // on, and the container keys that hold a section's models.
    private static let modelKeys = ["typeId", "semanticId", "protoMessageName",
                                    "observabilityViewName", "nox_diffableIdentifier"]
    private static let itemContainerKeys = ["items", "elements", "models", "children", "components", "rows"]

    static func log(adapter: NSObject, sections: NSArray?) {
        let adapterName = NSStringFromClass(type(of: adapter))
        guard adapterName.contains("ComponentCollectionViewAdapter") else { return }  // feed/SDUI only
        guard let sections = sections else { return }
        LProLog.write("[feed-inst] \(adapterName) setSections count=\(sections.count)")
        var logged = 0
        outer: for case let section as NSObject in sections {
            describe(section, tag: "section", loggedCount: &logged)
            for key in itemContainerKeys {
                guard let items = value(section, key) as? NSArray else { continue }
                for case let item as NSObject in items {
                    describe(item, tag: "item", loggedCount: &logged)
                    if logged >= 12 { break outer }
                }
                break
            }
            if logged >= 12 { break }
        }
    }

    private static func describe(_ object: NSObject, tag: String, loggedCount: inout Int) {
        var parts = ["\(tag)=\(NSStringFromClass(type(of: object)))"]
        for key in modelKeys {
            if let v = value(object, key) { parts.append("\(key)=\(v)") }
        }
        LProLog.write("[feed-inst]   \(parts.joined(separator: " "))")
        loggedCount += 1
    }

    private static func value(_ object: NSObject, _ key: String) -> Any? {
        guard object.responds(to: NSSelectorFromString(key)) else { return nil }
        return object.value(forKey: key)
    }
}
