import Orion
import UIKit
import ObjectiveC.runtime

// The primary settings entry: a "LinkedIn Professional" row directly ABOVE the
// "Settings & Privacy" row, INSIDE the Me-tab account panel's bottom box
// (NavPanelAccountAreaView).
//
// Runs from a single ClassHook<UIViewController> (viewDidLayoutSubviews), which
// always binds (NavPanelAccountAreaView is a Swift class not registered at
// launch, so hooking it by name aborted the group). Geometry observed in the
// live nav-panel dump: the box is frame-positioned and bottom-pinned, and its
// children keep their local positions when it grows. The applied height and the
// moved Settings-row Y are stored PER INSTANCE via associated objects, so a
// layout pass that LinkedIn re-runs does not stack another row and a reopened
// panel starts from its own natural geometry.
struct AccountPanelEntryGroup: HookGroup {}

private let lproRowTag = 0x4C50  // 'LP'
private let lproRowSeparatorTag = 0x4C51

class NavPanelVCHook: ClassHook<UIViewController> {
    typealias Group = AccountPanelEntryGroup

    func viewDidLayoutSubviews() {
        orig.viewDidLayoutSubviews()
        guard NSStringFromClass(type(of: target)).contains("NavPanelViewController") else { return }
        LProAccountEntry.apply(in: target.view)
        // The "Try Premium" upsell button is added to this panel during layout,
        // not at viewDidAppear, and LinkedIn can re-add it; re-hide every layout
        // pass while the option is on (idempotent - a hidden view stays hidden).
        if UserDefaults.lproFeedFilter.hidePremiumUpsell { LProPremium.hideUpsells() }
    }
}

// The account box is a plain, frame-positioned container (nav panel dump:
// {0,819,374,89} = 1pt divider + 16pt gap + 48pt Settings row + 24pt Premium
// strip). It is not a stack view, and its subviews keep their local positions
// when it grows, so adding a row means: grow the box upward by one row height
// and shift every sibling from the Settings row down by the same amount. That
// keeps the Settings row and the Premium strip at the same screen position and
// frees the slot directly under the divider for our row.
//
// LinkedIn re-runs its own layout after this hook, so the operation is redone
// whenever the geometry it produced is no longer present. The applied geometry
// is stored per area instance, so a reopened panel starts clean.
enum LProAccountEntry {
    private static var logged = false
    private static var swizzledClasses: [ObjectIdentifier] = []

    static func apply(in root: UIView?) {
        guard let root = root,
              let area = firstView(in: root, idContains: "AccountAreaViewA11yID") else { return }
        ensureLayoutFixer(area)
        applyToArea(area)
    }

    // Adds an override on the box's class whose block calls the implementation
    // it replaced and then re-applies the row. Deliberately NOT
    // method_exchangeImplementations: `class_getInstanceMethod` returns UIView's
    // inherited Method, and exchanging that swaps UIView's own layoutSubviews,
    // after which every plain UIView was sent our selector
    // (-[UIView ...]: unrecognized selector ... in layoutSublayersOfLayer).
    static func ensureLayoutFixer(_ area: UIView) {
        let cls: AnyClass = type(of: area)
        let id = ObjectIdentifier(cls)
        guard !swizzledClasses.contains(id) else { return }
        swizzledClasses.append(id)

        let sel = NSSelectorFromString("layoutSubviews")
        guard let method = class_getInstanceMethod(cls, sel) else { return }
        let types = method_getTypeEncoding(method)
        typealias Fn = @convention(c) (AnyObject, Selector) -> Void
        let orig = unsafeBitCast(method_getImplementation(method), to: Fn.self)

        let block: @convention(block) (AnyObject) -> Void = { obj in
            orig(obj, sel)
            LProAccountEntry.applyToArea(unsafeBitCast(obj, to: UIView.self))
        }
        let imp = imp_implementationWithBlock(block)
        if !class_addMethod(cls, sel, imp, types) {
            // The class implements layoutSubviews itself; replace it with a block
            // that calls the captured implementation first.
            method_setImplementation(method, imp)
        }
        LProLog.write("[entry] hooked layoutSubviews on \(NSStringFromClass(cls))")
    }

    static func applyToArea(_ area: UIView) {
        guard let host = area.superview,
              let settingsRow = firstView(in: area, idContains: "SettingsIconLabelView") else { return }

        let rowH = settingsRow.frame.height > 0 ? settingsRow.frame.height : 48

        // Our row is a sibling of the box, in the panel's own container, placed
        // directly above it. The box itself is NOT touched: LinkedIn re-lays it
        // out after every apply (log: "box keeps resetting"), so growing it can
        // never stick. A view we own is never laid out by LinkedIn, so this is
        // stable and cannot overlap the Settings row.
        let row = (host.viewWithTag(lproRowTag) as? UIControl) ?? makeRow()
        if row.superview !== host {
            row.tag = lproRowTag
            host.addSubview(row)
        }

        let box = area.convert(area.bounds, to: host)
        guard box.height > 8 else { return }  // box not laid out yet
        let target = CGRect(x: box.minX, y: box.minY - rowH, width: box.width, height: rowH)
        if !row.frame.equalTo(target) { row.frame = target }
        if let line = row.viewWithTag(lproRowSeparatorTag) {
            let h = 1 / UIScreen.main.scale
            let f = CGRect(x: 0, y: 0, width: row.bounds.width, height: h)
            if !line.frame.equalTo(f) { line.frame = f }
        }

        // Keep scrolled content from sliding under the row.
        if let scroll = firstScrollView(in: host), scroll.contentInset.bottom < rowH {
            var inset = scroll.contentInset
            inset.bottom = rowH
            scroll.contentInset = inset
        }

        if host.subviews.last !== row { host.bringSubviewToFront(row) }

        if !logged {
            logged = true
            LProLog.write("[entry] row \(target) above box \(box)")
        }
    }

    static func firstScrollView(in view: UIView) -> UIScrollView? {
        if let scroll = view as? UIScrollView { return scroll }
        for sub in view.subviews {
            if let found = firstScrollView(in: sub) { return found }
        }
        return nil
    }

    static func firstView(in view: UIView, idContains id: String) -> UIView? {
        if (view.accessibilityIdentifier ?? "").contains(id) { return view }
        for sub in view.subviews {
            if let found = firstView(in: sub, idContains: id) { return found }
        }
        return nil
    }

    private static func makeRow() -> UIControl {
        let button = UIButton(type: .system)
        button.addTarget(LProSettingsOpener.shared,
                         action: #selector(LProSettingsOpener.open), for: .touchUpInside)
        button.accessibilityLabel = "LinkedIn Professional"
        button.contentHorizontalAlignment = .leading
        // Opaque: the row sits over the panel's scroll content area.
        button.backgroundColor = .systemBackground

        let line = UIView()
        line.tag = lproRowSeparatorTag
        line.backgroundColor = .separator
        line.isUserInteractionEnabled = false
        button.addSubview(line)

        let icon = UIImageView(image: UIImage(systemName: "slider.horizontal.3"))
        icon.tintColor = .label
        icon.contentMode = .scaleAspectFit
        icon.translatesAutoresizingMaskIntoConstraints = false

        let label = UILabel()
        label.text = "LinkedIn Professional"
        label.font = .systemFont(ofSize: 16)
        label.textColor = .label
        label.translatesAutoresizingMaskIntoConstraints = false

        button.addSubview(icon)
        button.addSubview(label)
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: 16),
            icon.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 24),
            icon.heightAnchor.constraint(equalToConstant: 24),
            label.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: 48),
            label.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: button.trailingAnchor, constant: -16),
        ])
        return button
    }
}
