import Foundation
import ObjectiveC.runtime

// The cleanest way to stop premium-upsell injection: block the upsell content at
// the network source, so the app never receives any upsell payload to inject.
//
// From the captured traffic, the upsell cards are fetched by their own requests -
// voyagerPremiumDashUpsellSlotContent (BySlotUrns / BySlotType) and
// PremiumCancelFlowWinbackByUpsell. An NSURLProtocol matches those URLs and, when
// "hide premium upselling" is on, short-circuits them with an empty 200 ({"data":{}})
// instead of letting them reach the server - no content comes back, so nothing is
// injected or has to be hidden after the fact.
//
// Gated per-request on lproFeedFilter.hidePremiumUpsell (the single upsell control
// shared by the Ads and Premium panels); turning it off lets the requests through
// again live. The URL test runs first so the UserDefaults read only happens for the
// handful of upsell requests, not every request.
final class LProUpsellBlockProtocol: URLProtocol {
    static func isUpsellURL(_ url: String) -> Bool {
        let u = url.lowercased()
        return u.contains("upsellslot") || u.contains("cancelflowwinback")
            || u.contains("premiumdashupsell") || u.contains("premiumupsell")
    }

    // Feed "recommended" injected modules: companies / pages / people the algorithm
    // pushes in (voyagerFeedPackageRecommendations, the identity "people you may
    // know" module). Blocking these requests removes the modules at the source
    // instead of hiding their cells.
    static func isRecommendationURL(_ url: String) -> Bool {
        let u = url.lowercased()
        return u.contains("feedpackagerecommendations")
            || u.contains("identitymodulebymoduletype") || u.contains("feeddashidentitymodule")
    }

    override class func canInit(with request: URLRequest) -> Bool {
        guard let u = request.url?.absoluteString else { return false }
        let feed = UserDefaults.lproFeedFilter
        if isUpsellURL(u) { return feed.hidePremiumUpsell }
        if isRecommendationURL(u) { return feed.hidePromotions }
        return false
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url ?? URL(string: "https://www.linkedin.com/")!
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "application/json"])
            ?? HTTPURLResponse()
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("{\"data\":{}}".utf8))
        client?.urlProtocolDidFinishLoading(self)
        LProLog.write("[upsell] blocked \(url.absoluteString.prefix(90))")
    }

    override func stopLoading() {}
}

// Installs the upsell blocker (and, so there is a single configuration swizzle, the
// DevKit capture protocol too - its own canInit stays gated on the capture flag, so
// it does nothing unless capture is armed). Runs unconditionally at launch; the
// per-request gates decide whether anything is actually intercepted.
enum LProNetProtocols {
    private static var installed = false

    static func install() {
        guard !installed else { return }
        installed = true
        URLProtocol.registerClass(LProUpsellBlockProtocol.self)
        URLProtocol.registerClass(LProCaptureURLProtocol.self)

        let protos: [AnyClass] = [LProUpsellBlockProtocol.self, LProCaptureURLProtocol.self]
        for name in ["defaultSessionConfiguration", "ephemeralSessionConfiguration"] {
            let sel = NSSelectorFromString(name)
            guard let method = class_getClassMethod(URLSessionConfiguration.self, sel) else { continue }
            typealias Fn = @convention(c) (AnyObject, Selector) -> URLSessionConfiguration
            let orig = unsafeBitCast(method_getImplementation(method), to: Fn.self)
            let block: @convention(block) (AnyObject) -> URLSessionConfiguration = { obj in
                let config = orig(obj, sel)
                var classes = config.protocolClasses ?? []
                for proto in protos where !classes.contains(where: { $0 === proto }) {
                    classes.insert(proto, at: 0)
                }
                config.protocolClasses = classes
                return config
            }
            method_setImplementation(method, imp_implementationWithBlock(block))
        }
        LProLog.write("[upsell] network upsell blocker + capture protocol installed")
    }
}
