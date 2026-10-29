import Orion
import UIKit
import ObjectiveC.runtime

// The primary settings entry: a "LinkedIn Professional" row directly ABOVE the
// "Settings & Privacy" row, INSIDE the Me-tab account panel's bottom box
// (NavPanelAccountAreaView).
//
// Runs from a single ClassHook<UIViewController> (viewDidLayoutSubviews), which
// always binds (NavPanelAccountAreaView is a Swift class not registered at
// launch, so hooking it by name aborted the group). The box is frame-positioned
// and bottom-pinned, so we grow it upward by one row and place our row between
// its divider and the Settings row. The box's natural (pre-grow) height is stored
// PER INSTANCE via an associated object, so re-growing each layout pass is
// deterministic and never drifts across open/close - the bug behind the earlier
// "glued together" rows was a process-wide accumulating height.
struct AccountPanelEntryGroup: HookGroup {}

private let lproRowTag = 0x4C50  // 'LP'

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

enum LProAccountEntry {
    private static var logged = false
    private static var naturalKey: UInt8 = 0

    static func apply(in root: UIView?) {
        guard let root = root,
              let area = firstView(in: root, idContains: "AccountAreaViewA11yID"),
              let settingsRow = firstView(in: area, idContains: "SettingsIconLabelView") else { return }

        let rowH = settingsRow.frame.height > 0 ? settingsRow.frame.height : 48

        // Natural (pre-grow) height, stored on THIS area instance. A fresh panel
        // is a fresh instance with a fresh natural, so nothing accumulates.
        let natural: CGFloat
        if let stored = objc_getAssociatedObject(area, &naturalKey) as? CGFloat {
            natural = stored
        } else {
            guard area.frame.height > rowH else { return }  // not laid out yet
            natural = area.frame.height
            objc_setAssociatedObject(area, &naturalKey, natural, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
        let grown = natural + rowH

        // Grow the box upward (it is bottom-pinned): keep maxY, raise the top.
        if abs(area.frame.height - grown) > 0.5 {
            area.frame = CGRect(x: area.frame.minX, y: area.frame.maxY - grown,
                                width: area.frame.width, height: grown)
        }

        if !logged {
            logged = true
            LProLog.write("[entry] area=\(area.frame) natural=\(natural) rowH=\(rowH)")
        }

        // Our row sits INSIDE the box, directly above the Settings row.
        let row = (area.viewWithTag(lproRowTag) as? UIControl) ?? makeRow()
        if row.superview !== area {
            row.tag = lproRowTag
            area.addSubview(row)
        }
        let bottom = area.bounds.height
        settingsRow.frame = CGRect(x: settingsRow.frame.minX, y: bottom - rowH,
                                   width: settingsRow.frame.width, height: rowH)
        row.frame = CGRect(x: settingsRow.frame.minX, y: bottom - 2 * rowH,
                           width: settingsRow.frame.width, height: rowH)
        area.bringSubviewToFront(row)
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
