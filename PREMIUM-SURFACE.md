# LinkedIn Premium — client-side surface map

Research notes: where the iOS client keeps premium state, what it checks, what it
asks the server, and which UI it gates. Everything below is read from the
decrypted binary's ObjC metadata (main executable + VoyagerLibs) and its strings.
No behaviour is asserted; these are the symbols that exist in build
`2026.1021.1050` (build `9.32.5021`).

## 1. Membership state (client)

| Class | Selector | Encoding |
|---|---|---|
| `LINAuthConfigurationManager` | `-isPremiumSubscriber` | `BOOL` |
| `Me` (VoyagerLibs) | `-premiumSubscriber` | `NSNumber` |
| `DashProfile` (VoyagerLibs) | `-premium` | `NSNumber` |
| `DashProfile` | `-showPremiumSubscriberBadge` | `NSNumber` |
| `LINEntityCardData` / Builder | `-isPremium` / `-setIsPremium:` | `BOOL` |
| `LINLEIADashboardConfig` | `-isPremium` | `BOOL` |
| `LINLearningConsumptionViewController` | `-isPremiumOrLearningSubscriber` | `BOOL` |
| `_TtC12Marketplaces43...ContentViewData` | `-hasPremiumAccess` | `BOOL` |

`LINAuthConfigurationManager` is the central one: its premium-feature-access
requests (below) run from the same class.

## 2. Per-feature access

`PremiumFeatureAccess` (VoyagerLibs `RecordTemplate`) carries:

```
canViewWVMP                      NSNumber
canBrowseProfiles                NSNumber
canViewJobAnalytics              NSNumber
canViewCompanyInsights           NSNumber
canAccessLearningVideos          NSNumber
premiumFreeTrialEligible         NSNumber
premiumLearningUpgradeEligible   NSNumber
reactivationFeaturesEligible     BOOL(_Raw)
```

`DashFeatureAccess` (RecordTemplate) is a generic flag: `entityUrn`,
`featureAccessType`, `hasAccess`. `DashFeatureAccessType` is an enum template.

## 3. How the client learns entitlements (network)

Request builders on `LINAuthConfigurationManager`:

```
-premiumFeatureAccessRequestWithExecutor:
-premiumFeatureAccessGraphQLRequestWithExecutor:
```

GraphQL operation names in the binary:

```
GetPremiumFeatureAccessByAccessTypes
GetPremiumFeatureAccessByFeatureAccessTypes
PremiumFeatureAccessByCompany
```

Plus `LINPremiumGraphQLClient -getPremiumFeatureAccessByAccessTypes:` and
`-getPremiumCustomActionDetailsByViewee:`.

The access types are server-defined strings. Examples present in the binary:

```
CAN_ACCESS_MY_PREMIUM, CAN_ACCESS_MY_PREMIUM_V2, CAN_ACCESS_SMALL_BUSINESS_MY_PREMIUM
CAN_ACCESS_PREMIUM_COACH, CAN_ACCESS_PREMIUM_PAGE, CAN_ACCESS_PREMIUM_PAGE_PLUS
CAN_ACCESS_PREMIUM_REFERRALS, CAN_ACCESS_PREMIUM_TWO_SIDED_REFERRALS
CAN_ACCESS_PROFILE_PREMIUM_SPOTLIGHT, CAN_ACCESS_PROFILE_PREMIUM_FEATURED_SECTION
CAN_ACCESS_PROFILE_TOP_CARD_FORM_PREMIUM_SETTINGS, CAN_ACCESS_LEARNING_ENTERPRISE
CAN_ACCESS_LEARNING_BADGE, CAN_ACCESS_LYNDA_PREMIUM, CAN_ACCESS_INMAIL_MESSAGES
CAN_ACCESS_INMAIL_FOLLOW_UPS, CAN_ACCESS_SALES_NAV_ENTRY_POINT, CAN_ACCESS_SALES_NAV_BADGE
CAN_ACCESS_FREEMIUM_SALES_NAV_RELATIONSHIP_EXPLORER, CAN_ACCESS_RECRUITER_ENTRY_POINT
CAN_ACCESS_RECRUITER_MAILBOX, CAN_ACCESS_RECRUITER_MESSAGE_BUTTON
```

## 4. Product / storefront model

`PremiumPremiumProducts`: `products`, `promotionOffered`,
`recommendedProductIndex`, `socialProofInsight`, `footer`, `header`,
`warningText`.
`PremiumPremiumProduct`: `productId`, `productCode`, `productFamily`,
`productName`, `productDesc`, `actions`, `allFeatures`, `highlightedFeatures`,
`faqs`, `fixedTerm`, `promotion`, `taxType`, `taxLocationSource`.
Enum templates: `PremiumProductType`, `PremiumProductCode`,
`PremiumPremiumProductCode`, `PremiumProductFamily`, `PremiumPremiumProductFamily`,
`PremiumMyPremiumTypeEnum`, `DashMyPremiumTypeEnum`, `DashPremiumProductFamily`.

Family/value strings present: `CAREER`, `LEARNING`, `MY_PREMIUM`,
`MY_PREMIUM_EXPLORE_ALL`, `MY_PREMIUM_SETTINGS`, `MY_PREMIUM_SIDE_PANEL`,
`INMAIL*` (credits, templates, insights, upsell …).

Storefront bootstrap: `LINBootstrap -willLaunchMainWindowPremium`,
`-initPremiumStorefrontCache`.

## 5. Endpoints and routes

```
/premium/products
/premium/webviewer/
https://www.linkedin.com/premium/
https://www.linkedin.com/premium/my-premium
https://www.linkedin.com/premium/switcher
/mypreferences/m/premium-manage-account
/care/embed/copilot/premiumChooserChatMobile
linkedin://messaging/premium-magic-wand-learn-more
```

Navigation factories in `LINNavigatorMapping` for subscription, welcome flow,
redeem (plan/coupon), cancellation, onboarding, my-premium pages, saved
prospects, matches, referrals, and the products chooser
(`neptunePremiumProductsViewControllerWithFamily:channel:trk:…`).

## 6. Upsell surfaces (UI classes)

Jobs (`JobsHomePremiumHeader*`, `JobCollectionPremiumUpsell*`,
`SeekerNextBestActionPremiumUpsell*`, `HowYouMatchPremiumUpsell*`), Pages admin
(`PagesPremiumAutoInvite*`, `PagesPremiumAdditionalCreditsUpsell*`,
`PagesPremiumInviteToFollowUpsell*`), Marketplace (`…ProviderRequestsPremiumUpsell*`),
Messaging (`ConversationPremiumCustomButton*`, `PremiumReferralCoupon*`),
Events (`EventPremiumEventsBanner*`), Skills (`SkillMatchPremiumBrandingView`),
plus `PremiumNavPanelUpsellView` in the Me panel and
`LINPremiumFeatureAccessInterstitial*` interstitials.

LIX / experiment gates seen in selectors: `LINPremiumLixContainer
-pagesMemberNileEntitlementRedirect`, `LINPremiumWelcomeFlowFeature
-isPremiumTipsEnabled`, `LINPremiumChooserMultiStepIntentSurveyPageViewController
-isSduiPremiumChooserEntryPointEnabled`, `SDUI -isPremiumUpsellDebugEnabled`.

## 7. Client vs server

Client state (section 1) and the `PremiumFeatureAccess` record gate **what the UI
shows**: badges, headers, upsell visibility, entry points, interstitials.

The data behind premium features arrives from the server in the same
`GetPremiumFeatureAccessByAccessTypes` response and in each feature's own
payload (who-viewed-your-profile list, InMail credits, Learning streams,
company insights). Those payloads are populated server-side; the client has no
local copy to unlock.

## 8. Inspecting further on a live build

```
uivc / uitree                # which upsell views are on screen
classes Premium              # every premium-named class
methods <Class>              # selectors + type encodings
logtail <n> <tmp>/linkedinpro.log
```

Avoid `instances` on this build (it traps in malloc enumeration, see
`CONTINUE-HANDOFF.md`).
