import Foundation

// Applies a change from the Premium feature panel.
//
// Most of the panel's flags are read live by the spoof hooks (PremiumSpoof reads
// UserDefaults.lproPremium on every call via LProPremiumState.flag), so no push
// is needed for those - they take effect on the next check. The one flag with an
// immediate on-screen effect is "Hide upgrade prompts": re-run the shared view
// sweep so upsells already on screen are hidden (or restored) right away.
enum PremiumEnabler {
    static func sync(_ options: PremiumOptions) {
        LProViewSweeper.schedule()

        let clientOn = PremiumFeatureCatalog.groups
            .flatMap { $0.items }
            .filter { $0.effect == .clientSide && options.isEnabled($0.id) }
            .count
        let clientTotal = PremiumFeatureCatalog.clientSideIDs.count
        LProLog.write("[premium] spoof=\(options.spoofPremium) client-side flags on: \(clientOn)/\(clientTotal)")
    }
}
