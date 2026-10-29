import Orion
import UIKit

// The primary settings entry: a "LinkedIn Professional" row directly ABOVE
// LinkedIn's "Settings & Privacy" row in the Me-tab account panel.
//
// Confirmed on-device (Striker dump of HomeNav.NavPanelViewController): the
// Settings row is a NavPanelMenuItemView (a11y id
// NavPanelAccountAreaViewSettingsIconLabelView) inside NavPanelAccountAreaView
// (a11y id ...AccountAreaViewA11yID), a bottom-pinned area. We overlay our own
// row just above that area, in its superview, so we don't fight the area's
// internal auto-layout.
//
// Hooks UIViewController.viewDidLayoutSubviews (always present) and filters by
// class name, instead of binding the lazily-registered Swift VC by name.
struct AccountPanelEntryGroup: HookGroup {}

class NavPanelLayoutHook: ClassHook<UIViewController> {
    typealias Group = AccountPanelEntryGroup

    func viewDidLayoutSubviews() {
        orig.viewDidLayoutSubviews()
        guard NSStringFromClass(type(of: target)).contains("NavPanelViewController") else { return }
        LProAccountEntry.apply(in: target.view)
    }
}

enum LProAccountEntry {
    private static let tag = 0x4C50  // 'LP'
    private static let rowHeight: CGFloat = 48

    static func apply(in root: UIView?) {
        guard let root = root,
              let area = firstView(in: root, idContains: "AccountAreaViewA11yID"),
              let container = area.superview else { return }

        let row = (container.viewWithTag(tag) as? UIControl) ?? makeRow()
        if row.superview == nil {
            row.tag = tag
            container.addSubview(row)
        }
        row.frame = CGRect(x: area.frame.minX, y: area.frame.minY - rowHeight,
                           width: area.frame.width, height: rowHeight)
        container.bringSubviewToFront(row)
    }

    private static func firstView(in view: UIView, idContains id: String) -> UIView? {
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
