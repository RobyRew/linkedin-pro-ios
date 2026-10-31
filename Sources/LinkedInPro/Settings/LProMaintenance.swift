import Foundation

// Maintenance actions for the main tweak settings: clear LinkedIn's cache, clear
// cache + data, and restore the tweak's own defaults. All operate on the app's own
// sandbox; each returns a short result line for the settings UI.
enum LProMaintenance {
    // MANDATORY (see AGENTS.md): every feature that stores a UserDefaults key or a
    // marker file MUST add it here, so "Restore tweak's default settings" really
    // returns the whole tweak to its shipped state. Keep this list complete.
    private static let tweakDefaultsKeys = [
        "lproFeedFilter",        // feed + ads filters
        "lproTabBar",            // nav-bar order / glass / launch tab
        "lproPremium",           // premium spoof flags
        "lproDevKitEnabled",     // Striker on/off
        "lproFeedCaptureEnabled",// DevKit feed capture
    ]

    private static func emptyDirectory(_ path: String?) -> Int {
        guard let path else { return 0 }
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(atPath: path) else { return 0 }
        var removed = 0
        for item in items {
            let full = (path as NSString).appendingPathComponent(item)
            if (try? fm.removeItem(atPath: full)) != nil { removed += 1 }
        }
        return removed
    }

    private static func caches() -> String? {
        NSSearchPathForDirectoriesInDomains(.cachesDirectory, .userDomainMask, true).first
    }
    private static func library() -> String? {
        NSSearchPathForDirectoriesInDomains(.libraryDirectory, .userDomainMask, true).first
    }

    // Clear LinkedIn's cache: the URL cache + Library/Caches + tmp. Keeps login and
    // app data; LinkedIn rebuilds the cache on next use.
    @discardableResult
    static func clearCache() -> String {
        URLCache.shared.removeAllCachedResponses()
        var n = emptyDirectory(caches())
        n += emptyDirectory(NSTemporaryDirectory())
        LProLog.write("[maint] cleared cache (\(n) item(s))")
        return "Cleared \(n) cache item(s). Relaunch LinkedIn to rebuild them."
    }

    // Clear cache & data (all): the above plus cookies and the whole Library
    // (WebKit, Cookies, Preferences, Application Support). This resets LinkedIn's
    // local state and signs you out. Documents is left intact (it holds the
    // file-sharing / capture files).
    @discardableResult
    static func clearCacheAndData() -> String {
        URLCache.shared.removeAllCachedResponses()
        HTTPCookieStorage.shared.cookies?.forEach { HTTPCookieStorage.shared.deleteCookie($0) }
        var n = emptyDirectory(library())
        n += emptyDirectory(NSTemporaryDirectory())
        LProLog.write("[maint] cleared cache & data (\(n) item(s))")
        return "Cleared \(n) item(s) of cache and app data. This signs you out \u{2014} force-quit and relaunch LinkedIn."
    }

    // Restore the tweak's default settings: remove every stored key (so the shipped
    // defaults apply), drop the cached decodes, and reset the Liquid Glass marker to
    // its default. LinkedIn Professional returns to a fresh-install state.
    @discardableResult
    static func resetTweakDefaults() -> String {
        for key in tweakDefaultsKeys { UserDefaults.standard.removeObject(forKey: key) }
        LProFeedFilterCache.invalidate()
        LProPremiumState.invalidate()
        LProGlassFlag.set(TabBarOptions().iOS26GlassTabs)
        LProLog.write("[maint] restored tweak defaults (\(tweakDefaultsKeys.count) keys)")
        return "Restored LinkedIn Professional to its default settings. Relaunch to apply all of them."
    }
}
