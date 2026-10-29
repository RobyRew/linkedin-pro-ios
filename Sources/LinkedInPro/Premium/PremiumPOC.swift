import Foundation

// Receives every change from the Premium feature panel. It records what was
// changed and returns; no hook, override or view reads these flags. Present so
// the settings toggles have a defined, crash-free sink.
enum PremiumPOC {
    static func sync(_ options: PremiumOptions) {
        LProLog.write("[premium-poc] \(options.enabledCount)/\(options.featureCount) feature flags on")
    }
}
