import Foundation
import UIKit

// LinkedIn-specific logging façade over tweak-kit's shared TweakLog (file +
// NSLog). The log file is pullable over USB with striker / devicectl.
enum LProLog {
    private static let log = TweakLog(tag: "LinkedInPro", filename: "linkedinpro.log")

    static func write(_ message: String) { log.write(message) }

    // Records the exact build and host environment at launch, so a bug report or
    // a USB log pull identifies which LinkedIn build / iOS version produced it.
    static func boot() {
        write("=== LinkedInPro build \(GeneratedConfig.buildStamp) (\(GeneratedConfig.commit)) starting ===")
        write("[boot] LinkedIn \(LinkedInVersion.short) (build \(LinkedInVersion.build))")
        write("[boot] iOS \(UIDevice.current.systemVersion), device \(LinkedInVersion.deviceModel)")
    }
}
