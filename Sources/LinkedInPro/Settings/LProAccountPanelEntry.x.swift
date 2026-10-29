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
    }
}

enum LProAccountEntry {
    static var oneRowHeight: CGFloat = .greatestFiniteMagnitude

    static func apply(in root: UIView?) {
        guard let root = root,
              let area = firstView(in: root, idContains: "AccountAreaViewA11yID"),
              let settingsRow = firstView(in: area, idContains: "SettingsIconLabelView") else { return }

        let rowH = settingsRow.frame.height > 0 ? settingsRow.frame.height : 48
        oneRowHeight = min(oneRowHeight, area.frame.height)
        let targetHeight = oneRowHeight + rowH

        // Grow the bottom bar upward by one row, keeping its bottom pinned.
        if area.frame.height < targetHeight - 0.5 {
            let bottom = area.frame.maxY
            area.frame = CGRect(x: area.frame.minX, y: bottom - targetHeight,
                                width: area.frame.width, height: targetHeight)
        }

        let row = (area.viewWithTag(lproRowTag) as? UIControl) ?? makeRow()
        if row.superview !== area {
            row.tag = lproRowTag
            area.addSubview(row)
        }

        // Pin Settings to the bottom of the grown bar; our row sits just above it.
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
