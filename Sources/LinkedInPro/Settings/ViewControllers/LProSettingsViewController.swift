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

        // SwiftUI NavigationLink needs a SwiftUI NavigationStack, which this flow
        // has not got (the view is shown on a UIKit nav controller). So the feature
        // rows push their sub-screen through this closure onto the same UIKit nav -
        // one native bar, native back, from either the pushed or modal entry path.
        let host = UIHostingController(rootView: LProSettingsView(push: { [weak self] view, title in
            guard let self, let nav = self.navigationController else { return }
            let sub = UIHostingController(rootView: view)
            sub.title = title
            nav.pushViewController(sub, animated: true)
        }))
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
