# LinkedIn Premium — deep analysis of flags, checks and calls

Companion to `PREMIUM-SURFACE.md` (the short map). This file records the full
client-side premium system as it exists in build `2026.1021.1050`
(build `9.32.5021`): the state hub, the fetch chain, every entitlement access
type present in the binaries, the commerce models, the gates, and what is stored
where. All of it is read from the decrypted binaries (ObjC metadata + strings).
No behaviour is asserted.

## 1. State hub: LINAuthConfigurationManager

Everything premium converges on `LINAuthConfigurationManager` (main binary).
Properties:

```
isPremiumSubscriber            BOOL
premiumFeatureAccess           PremiumFeatureAccess        (setter + getter)
premiumDashFeatureAccess       PremiumFeatureAccessByCompany
me, miniProfile, dashProfile
meSettings, messagingSettings, privacySettings, configuration
authExecutor, authLixManager, rootContainerProvider
listeners (addListener:)
extUserDefaults
```

So a single object holds the membership flag, the per-feature access record, the
per-company record and the raw session objects.

## 2. The fetch chain

Recording string from the binary:

```
failed to fetch multiplexed configuration, me, meSettings, and premiumFeatureAccess: %@
```

i.e. one multiplexed GraphQL request returns **configuration + me + meSettings +
premiumFeatureAccess**. Client entry points:

```
-fetchConfigurationDataWithCompletion:
-fetchMeWithPageInstance:completion:            -handleFetchMeResponse:
-fetchMeOnceWithPageInstance:completion:
-fetchGraphQLMeWithPageInstance:retryCount:delaySeconds:completion:
-fetchMeSettingsWithCompletion:                 -handleFetchMeSettingsResponse:
-fetchMessagingSettings                         -handleFetchMessagingSettingsResponse:
-fetchPrivacySettingsWithCompletion:            -handleFetchPrivacySettingsResponse:
-premiumFeatureAccessRequestWithExecutor:       -handleFetchPremiumFeatureAccessResponse:
-premiumFeatureAccessGraphQLRequestWithExecutor:
                                                -handleFetchPremiumDashFeatureAccessResponse:
                                                -handleFetchSuperLikeStatusResponse:
-buildMeRequestBuilderWithPageInstance:
-buildDashProfileRequestBuilderWithPageInstance:
-cleanUpUserDefaults
```

The two premium handlers store into `premiumFeatureAccess` /
`premiumDashFeatureAccess`; `addListener:` notifies observers when that happens.

## 3. Feature-access records

`PremiumFeatureAccess` (VoyagerLibs, `RecordTemplate`):

```
canViewWVMP                    NSNumber
canBrowseProfiles              NSNumber
canViewJobAnalytics            NSNumber
canViewCompanyInsights         NSNumber
canAccessLearningVideos        NSNumber
premiumFreeTrialEligible       NSNumber
premiumLearningUpgradeEligible NSNumber
reactivationFeaturesEligible   BOOL   (reactivationFeaturesEligible_Raw)
```

`DashFeatureAccess` (generic): `entityUrn`, `featureAccessType`, `hasAccess`.
`DashFeatureAccessType`, `PremiumPremiumFeatureType` are enum templates.
`PremiumFeatureAccessByCompany` is the per-page/company variant, fetched by
`LINInfraGraphQLClient -premiumFeatureAccessByFeatureAccessTypes:` and
`LINPremiumGraphQLClient -getPremiumFeatureAccessByAccessTypes:`.

GraphQL operation names in the binary:

```
GetPremiumFeatureAccessByAccessTypes
GetPremiumFeatureAccessByFeatureAccessTypes
PremiumFeatureAccessByCompany
```

## 4. Entitlement access types (54 strings)

These are the server-defined identifiers the client asks about:

```
ADVERTISE_BADGE                    ENGAGEMENT_ANALYTICS              PREMIUM_PAGE_PRO
AWAY_MESSAGES                      FOLLOWER_COUNT_SEARCH_FILTER      PREMIUM_PAGE_REVERSE_TRIAL
DECISION_MAKERS                    FREEMIUM_SALES_NAV_RELATIONSHIP_EXPLORER
GENERATED_MESSAGES                 HIRING_MANAGER_MAILBOX            PREMIUM_REFERRALS
GENERATED_PROFILE_CONTENT          HOW_YOU_MATCH_TOP_SKILLS_INSIGHT  PREMIUM_TWO_SIDED_REFERRALS
INMAIL_FOLLOW_UPS                  INMAIL_MESSAGES                   PROFILE_CUSTOM_CTA
INSIGHTS_BADGE                     INTERVIEW_PREP                    PROFILE_NEMO_STOREFRONT
JOBSEEKER_SEARCH_FILTERS           JOB_APPLICANT_INSIGHTS            PROFILE_PREMIUM_FEATURED_SECTION
JOB_POSTING_COMPANY_INSIGHTS       LEARNING_BADGE                    PROFILE_PREMIUM_SPOTLIGHT
LEARNING_ENTERPRISE                LYNDA_PREMIUM                     PROFILE_TOP_CARD_FORM_PREMIUM_SETTINGS
MEMBER_POST_BOOSTING               MY_PREMIUM                        RECRUITER_ENTRY_POINT
MY_PREMIUM_V2                      ORGANIZATION_COMPANY_INSIGHTS     RECRUITER_MAILBOX
PREMIUM_COACH                      PREMIUM_PAGE                      RECRUITER_MESSAGE_BUTTON
PREMIUM_PAGE_PLUS                  RESUME_KEYWORD_INSIGHTS           SALES_NAV_BADGE
SALES_NAV_ENTRY_POINT              SERVICE_MARKETPLACE_PROMO         SERVICE_PROVIDER_LEADS
SMALL_BUSINESS_MY_PREMIUM          SMALL_BUSINESS_POST_BOOSTING      SUBS_MESSAGE_BUTTON
TOP_APPLICANT_INSIGHTS             TOP_APPLICANT_JOBS                TOP_CHOICE
UNLIMITED_CUSTOM_INVITE            WHO_VIEWED_MY_PROFILE             WHO_VIEWED_MY_PROFILE_1_YEAR_LOOKBACK
WRITING_ASSISTANT
```

(All strings are prefixed `CAN_ACCESS_` in the binary; 54 distinct values.)

## 5. Commerce / product model

Records: `PremiumPremiumProducts {products, promotionOffered,
recommendedProductIndex, socialProofInsight, header, footer, warningText}`,
`PremiumPremiumProduct {productId, productCode, productFamily, productName,
productDesc, actions, allFeatures, highlightedFeatures, faqs, fixedTerm,
promotion, taxType, taxLocationSource}`.

Enums: `PremiumProductType`, `PremiumProductCode`, `PremiumProductFamily`,
`PremiumPremiumProductCode`, `PremiumPremiumProductFamily`,
`PremiumMyPremiumTypeEnum`, `DashMyPremiumTypeEnum`, `DashPremiumProductFamily`.
Value strings include `CAREER`, `LEARNING`, `MY_PREMIUM` and the `MY_PREMIUM_*`
surface names.

Storefront: `LINBootstrap -willLaunchMainWindowPremium` /
`-initPremiumStorefrontCache`, `LINPremiumSKProductsResource` (StoreKit product
list), `_TtC14PremiumAPIImpl25LIPProductManagerProvider` and
`…26LIPPurchaseManagerProvider` (LIP = LinkedIn in-app purchase).

## 6. Routes used by the premium flows

```
/premium/products
/premium/webviewer/
https://www.linkedin.com/premium/
https://www.linkedin.com/premium/my-premium
https://www.linkedin.com/premium/switcher
/mypreferences/m/premium-manage-account
/care/embed/copilot/premiumChooserChatMobile
```

Plus the `LINNavigatorMapping -neptunePremium*` family: subscription, welcome
flow, redeem (plan / coupon / gift), cancellation, onboarding (coach / learning
/ recruiter / sales), my-premium (manage / explore / trending), saved prospects,
matches, referrals, accept (enterprise), products chooser.

## 7. UI gates (groups seen in the binary)

- Membership: `LINFeedHeaderPresenterStyle -shouldDisplayPremiumBar` /
  `-shouldDisplayPremiumLogoV2`, `LINFormInputSwitchViewData
  -shouldShowPremiumBar`, `LINFeedActorStyle -showPremiumCTA`,
  `LINEntityCardData -isPremium`, `Me -premiumSubscriber`,
  `DashProfile -premium` / `-showPremiumSubscriberBadge`.
- Analytics: `LINLEIADashboardConfig -isPremium`, `LINLEIACardsStateManager
  -isPremiumChipEligibleCardURN:`, `LINLEIACardTransformer …showPremiumChip:`,
  `LIXLEIAContainer -isProfileAnalyticsRebrandPremiumChipEnabledForManager:`.
- Learning: `LINLearningConsumptionViewController -isPremiumOrLearningSubscriber`.
- Jobs: `HowYouMatchPremiumUpsell*`, `JobCollectionPremiumUpsell*`,
  `JobsHomePremiumHeader*`, `SeekerNextBestActionPremiumUpsell*`,
  `JobsPremiumUpsellBottomSheetActionViewData`.
- Pages: `PagesPremiumAutoInvite*`, `PagesPremiumAdditionalCreditsUpsell*`,
  `PagesPremiumInviteToFollowUpsell*`, `PagesPremiumGradient*`.
- Marketplace: `…ProviderRequestsPremiumUpsell*`, `MarketplacesGraphQLClient
  -marketplaceProjectsByServiceMarketplaceProvider:…isPremiumRequest:…`.
- Messaging: `ConversationPremiumCustomButton*`, `PremiumReferralCoupon*`,
  `DashMessagingPremiumAIEntryPointCTA`, `DashMessagingPremiumGeneratedMessage*`.
- Events / Skills: `EventPremiumEventsBanner*`, `SkillMatchPremiumBrandingView`.
- Me panel: `PremiumNavPanelUpsellView`, `LINPremiumFeatureAccessInterstitial*`.
- AI: `LINAISuggestionBar -handlePremiumUpsellLockCTATap`,
  `LINFormElementGAITextComponent -didTapPremiumUpsellLockCTA…`.

## 8. Experiment (LIX) gates

`_TtC14PremiumAPIImpl10PremiumLix -premiumEmbeddedSurveyTreatment`,
`PremiumContainer premiumLix`, `PremiumServiceFactory -makePremiumLix`,
`LINPremiumUpsellCardViewData premiumPostApplyPromoTreatmentV1/V2`,
`SDUI -isPremiumUpsellDebugEnabled`, `LINConfigSpec -createPremiumToggle`,
`-premiumUpsellDebugToggle`, `-premiumSubscriptionSwitcherTool`.

## 9. Stored keys and local state

Strings that back local storage / settings:
`isPremiumSubscriber`, `premiumFeatureAccess`, `premiumDashFeatureAccess`,
`premiumDashFeatureAccessByCompany`, `SHOW_PREMIUM_SUBSCRIBER_BADGE`,
`showPremiumBadge`, `my_premium_premium_tips_setting_update_success/failure`.
`LINAuthConfigurationManager -cleanUpUserDefaults` clears the cached session
objects on sign-out.

## 10. What is verified where

- The client only **reads** `isPremiumSubscriber`, `premiumFeatureAccess`,
  `premiumDashFeatureAccess` and the per-view flags above. Those decide UI.
- The same multiplexed response carries the data itself (viewer list, analytics
  numbers, InMail credits, Learning video URLs, applicant insights). That data
  is produced server-side; nothing local substitutes for it.
- Access types are evaluated server-side per request (`CAN_ACCESS_*`), so any
  per-feature answer can differ from the membership flag.

## 11. Observing it live (Striker)

```
methods LINAuthConfigurationManager          # full selector list on the running build
classes Premium                              # premium classes actually present
logtail <n> <tmp>/linkedinpro.log
```

Avoid `instances` (it traps in malloc enumeration on this build).
