import UIKit
import SwiftUI

// Plain UIViewController that embeds the SwiftUI settings screen. LinkedIn is
// UIKit, so no page-protocol spoofing is needed - this is pushed directly onto
// the host's navigation controller.
final class LProSettingsViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "LinkedIn Professional"
        view.backgroundColor = .systemBackground

        let host = UIHostingController(rootView: LProSettingsView())
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        host.didMove(toParent: self)
    }
}
