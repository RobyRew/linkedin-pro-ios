import Orion
import UIKit

// The primary settings entry: a "LinkedIn Professional" row directly ABOVE the
// "Settings & Privacy" row, INSIDE the Me-tab account panel's bottom bar.
//
// Confirmed on-device (Striker dump of HomeNav.NavPanelViewController): the bar
// is HomeNav.NavPanelAccountAreaView (a11y id ...AccountAreaViewA11yID), a
// bottom-pinned area ~65pt tall holding a divider + the Settings row
// (NavPanelMenuItemView, a11y id NavPanelAccountAreaViewSettingsIconLabelView).
//
// Two hooks:
//   1. NavPanelViewController.viewDidLayoutSubviews grows the bar by one row,
//      keeping its bottom pinned (the VC owns the bar's frame).
//   2. NavPanelAccountAreaView.layoutSubviews bottom-aligns the Settings row and
//      places our row just above it, inside the (now taller) bar - so it's
//      frontmost and tappable, not floating over the scroll view.
struct AccountPanelEntryGroup: HookGroup {}

private let lproRowTag = 0x4C50  // 'LP'
private let lproRowHeight: CGFloat = 48

class NavPanelVCHook: ClassHook<UIViewController> {
    typealias Group = AccountPanelEntryGroup

    func viewDidLayoutSubviews() {
        orig.viewDidLayoutSubviews()
        guard NSStringFromClass(type(of: target)).contains("NavPanelViewController"),
              let area = LProAccountEntry.firstView(in: target.view, idContains: "AccountAreaViewA11yID")
        else { return }
        // Capture the natural one-row height, then keep the bar grown by one row.
        LProAccountEntry.oneRowHeight = min(LProAccountEntry.oneRowHeight, area.frame.height)
        let targetHeight = LProAccountEntry.oneRowHeight + lproRowHeight
        if area.frame.height < targetHeight - 0.5 {
            let bottom = area.frame.maxY
            area.frame = CGRect(x: area.frame.minX, y: bottom - targetHeight,
                                width: area.frame.width, height: targetHeight)
        }
    }
}

class NavPanelAccountAreaHook: ClassHook<UIView> {
    typealias Group = AccountPanelEntryGroup
    static let targetName = "HomeNav.NavPanelAccountAreaView"

    func layoutSubviews() {
        orig.layoutSubviews()
        LProAccountEntry.layout(in: target)
    }
}

enum LProAccountEntry {
    static var oneRowHeight: CGFloat = .greatestFiniteMagnitude

    static func layout(in area: UIView) {
        guard let settingsRow = area.subviews.first(where: {
            ($0.accessibilityIdentifier ?? "").contains("SettingsIconLabelView")
        }) else { return }

        let row = (area.viewWithTag(lproRowTag) as? UIControl) ?? makeRow()
        if row.superview !== area {
            row.tag = lproRowTag
            area.addSubview(row)
        }

        let rowH = settingsRow.frame.height > 0 ? settingsRow.frame.height : lproRowHeight
        // Pin the Settings row to the bottom of the (grown) bar; our row sits
        // directly above it.
        let settingsY = area.bounds.height - rowH
        settingsRow.frame = CGRect(x: settingsRow.frame.minX, y: settingsY,
                                   width: settingsRow.frame.width, height: rowH)
        row.frame = CGRect(x: 0, y: settingsY - rowH, width: area.bounds.width, height: rowH)
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
