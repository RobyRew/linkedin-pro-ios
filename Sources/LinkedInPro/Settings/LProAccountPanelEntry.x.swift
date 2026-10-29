import Orion
import UIKit

// The primary settings entry: a "LinkedIn Professional" row directly ABOVE the
// "Settings & Privacy" row, INSIDE the Me-tab account panel's bottom bar.
//
// Everything runs from a single ClassHook<UIViewController> (viewDidLayoutSubviews),
// which always binds - a previous attempt also hooked the Swift class
// HomeNav.NavPanelAccountAreaView by name, but that class isn't registered at
// launch, so its activation failed and aborted the whole group. The VC hook runs
// after the bar has laid out, so growing the bar + repositioning its rows here
// sticks (re-applied each layout).
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

    // The account area (NavPanelAccountAreaView) is frame-positioned by the panel,
    // pinned to the bottom, and is NOT a stack view (just a divider + the single
    // "Settings & Privacy" row). Growing it and repositioning its rows each layout
    // fought the panel's own layout and drifted across open/close ("glued
    // together"). Instead we place OUR row as a sibling of the area, in the panel
    // view, directly above the area - a pure function of the area's frame each
    // pass. LinkedIn's views are never mutated, so there is nothing to drift.
    static func apply(in root: UIView?) {
        guard let root = root,
              let area = firstView(in: root, idContains: "AccountAreaViewA11yID"),
              let host = area.superview else { return }

        let settingsRow = firstView(in: area, idContains: "SettingsIconLabelView")
        let rowH = (settingsRow?.frame.height ?? 0) > 0 ? settingsRow!.frame.height : 48

        if !logged {
            logged = true
            LProLog.write("[entry] area=\(area.frame) host=\(NSStringFromClass(type(of: host))) rowH=\(rowH)")
        }

        let row = (host.viewWithTag(lproRowTag) as? UIControl) ?? makeRow()
        if row.superview !== host {
            row.tag = lproRowTag
            host.addSubview(row)
        }
        // Directly above the account area (its divider sits at the area's top).
        row.frame = CGRect(x: area.frame.minX, y: area.frame.minY - rowH,
                           width: area.frame.width, height: rowH)
        host.bringSubviewToFront(row)
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
