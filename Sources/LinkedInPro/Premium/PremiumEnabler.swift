import Foundation

// Receives every change from the Premium feature panel. It records what was
// changed and returns;
enum PremiumEnabler {
    static func sync(_ options: PremiumOptions) {
        LProLog.write("[premium-enabler] \(options.enabledCount)/\(options.featureCount) feature flags on")
    }
}
