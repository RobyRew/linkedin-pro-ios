# LinkedIn iOS — reverse-engineering notes

Facts below are either read from the decrypted binary's ObjC metadata (class-dump
style inventory of the main executable and VoyagerLibs) or observed in a live
Striker dump. Each section says which. Nothing here asserts that a feature works;
it records what exists in the build.

Build examined: LinkedIn `2026.1021.1050` (build `9.32.5021`), MinimumOS 18.0,
built with the iOS 26 SDK, `UIDesignRequiresCompatibility=1`. Device: iPhone 16
Pro Max, iOS 27.0.1 (`iPhone17,2`).

Inventory size: 19,008 ObjC classes / 151,168 methods in the main binary;
14,427 classes / 131,545 methods in VoyagerLibs.

## Live console

Striker is embedded in the tweak and listens on `127.0.0.1:45801`; over USB:

```
iproxy 45801 45801
STRIKER_PORT=45801 python3 driver/striker.py "uitree 80 20000"
```

It answers only while LinkedIn is foregrounded. Useful commands: `uivc`,
`uitree [depth] [nodes] [all]`, `uidump [depth] [nodes]` (writes
`NSTemporaryDirectory()/striker-uidump.json`), `classes <filter>`,
`methods <Class>`, `obj <addr>`, `sendq <obj> <sel>`.

## Main navigation / tab bar

`LINMainNavViewController` IS a `UITabBarController` (inventory). Its own methods
of interest: `viewControllers`, `setViewControllers:`, `setViewControllers:animated:`,
`sanitizedTabControllerViewControllers:`, `tabBar:didSelectItem:`,
`updateSelectedItem:tabBar:`, `applyUpdatedTabSelection`,
`indicatorLayer`, `previouslySelectedTabKey`, `isTabBarShorterThanNormal`,
`expectedTabBarHeight`, `adjustTabBarFrameIfNeeded`, `disableAllTabBarItems`,
`lin_shouldKeepReorderedTabNav`.

The tab set is server-driven and can vary per member; `sanitizedTabControllerViewControllers:`
and `invalidateTabsOrderCache` exist for that reason.

Tab types are produced by `_TtC14HomeNavAPIImpl21MainNavTabTypeFactory`
(`HomeNavAPIImpl.MainNavTabTypeFactory`), which exposes one zero-argument method
per type (inventory):

```
feed  messaging  myNetwork  jobs  notifications  post  video  trendsHub  games  more
tabTypeForTabString:  mainNavTabsOrder  invalidateTabsOrderCache
```

`LINMainNavTabType` carries `tabName`, `rawValue`, `value`, `tabIndex`,
`trackingControlName`. `post` is the center action built by
`MainNavFloatingActionButtonFactory -makeFloatingActionButtonForTabType:`, not a
bar tab.

Item construction: `LINTabBarItemFactory -makeTabBarItemForTabType:` returns a
`UITabBarItem` (its `.image` is the bar icon). Controllers:
`LINMainNavTabBarViewControllerFactory -makeViewControllerForTabType:`, or
`_TtC7HomeNav32AdaptiveTabViewControllerFactory
-makeAdaptiveTabViewController:rootContainer:tabType:`.
Selection lives in `LINRootViewControllerManager`:
`getViewControllerForTab:`, `firstViewControllerForTabType:`,
`selectMainNavTab:triggeredByUserInteraction:completion:`, `isCurrentlyInTab:`,

Live dump (b5-era, from `scratchpad/linkedinpro.log`): the bar is a `UITabBar`
with 5 `UITabBarButton`s, each 84 pt wide, one per visible tab; each button holds
a `LINTabBarBadgePlacementView` (badge), a `UITabBarSwappableImageView` (icon) and
a `UITabBarButtonLabel` (title). The Me tab is a separate
`LINMainNavMeButtonV2` (32×32) in the top bar, not one of the five.

### Tab-bar API — static validation (main binary, build 9.32.5021)

Counts of the tab-ordering selectors in the decrypted main executable
(`strings`), to decide which API the TabEngine must drive:

```
setViewControllers:                    6   (legacy UITabBarController API)
mainNavTabsOrder                       2
sanitizedTabControllerViewControllers: 1
setTabs:                               0   (modern iOS 18 UITab API)
UITab                                  0
tabForIdentifier                       0
customizationIdentifiers               0
```

So LinkedIn configures the bar through the legacy `viewControllers` API and does
not use the iOS 18 `UITab` API at all. On iOS 18+, assigning `viewControllers`
auto-populates `UITabBarController.tabs` with derived `UITab`s, so TabEngine's
`#available(iOS 18) && !tbc.tabs.isEmpty` branch reorders those in place
(identity-preserving); where `tabs` is empty it falls back to `setViewControllers`.
Both branches resolve a tab's name via title → identifier → VC class, so neither
drops a tab when icon-only mode blanks the title. The branch taken is logged at
runtime: `[navbar] applied (modern UITab)` vs `(viewControllers)`.

## Feed (SDUI)

Main feed: `VoyagerFeed.FeedSDUIViewController` → child
`SDUIScreenViewController` → `SDUI.Zen.ZenContentView` →
`SDUI.Zen.ComponentCollectionView` → cards of class
`SDUI.Zen.ComponentCollectionViewDataSource.ComponentCell`.

The data source's only two @objc entry points are
`collectionView:willDisplayCell:forItemAtIndexPath:` and
`collectionView:layout:sizeForItemAtIndexPath:` — the feed supplies explicit item
sizes, so a height of 0 collapses a card without leaving a gap.
`DashFeedUpdateBuilder.build:error:` never sees SDUI feed cards.

Card metadata is delivered as ACCESSIBILITY labels on `SDUI.TextBlockView`, not
as `UILabel.text`. Observed labels in one live feed dump:

```
Promoted                          View Sponsored Content
Asif Zahoor finds this funny      <name> likes this / commented on this (social proof)
View <name>’s profile             Reaction button state: no reaction
```

A post body is also an accessibility label, so classifying by text alone can hit
body copy; position separates them. In the dump the social-proof line sits at
y≈12 inside the cell, the author row at y≈45, the body from y≈140. The tweak
therefore only treats labels with `minY < 80` (cell space) as header/social
proof.

## Me tab — account panel

`HomeNav.NavPanelViewController` (a side panel, no navigation controller) with:

```
UIView id=NavPanelViewControllerMainPanelViewA11yID
  UIScrollView
    UIView id=NavPanelViewControllerScrollContentViewA11yID
      HomeNav.NavPanelIdentityView id=NavPanelViewControllerIdentityViewA11yID
        Profile.IdentityMirrorProfileView (avatar, name, headline, location)
        HomeNav.NavPanelAnalyticsEntryPointView
      ...
      HomeNav.NavPanelAccountAreaView id=NavPanelViewControllerAccountAreaViewA11yID  {0,843,374,65}
        HomeNav.NavPanelDividerView {0,843,374,1}
        HomeNav.NavPanelMenuItemView id=NavPanelAccountAreaViewSettingsIconLabelView {0,860,374,48}
          UIImageView {16,872,24,24}
          UILabel {48,876,310,16}   "Settings & Privacy"
```

The area is frame-positioned (no height constraint; 11 constraints on it),
bottom-pinned at 65 pt = 1 pt divider + 16 pt gap + 48 pt row. A row therefore
needs the box grown upward by 48 pt, with the Settings row moved down by the same
amount; a per-instance record of the natural height and of the Settings row's
original Y keeps repeated layout passes idempotent.

The "Try Premium" upsell is an `ARTButton` elsewhere in the panel and is re-added
during layout, so hiding it has to be re-applied per layout pass.

## Premium gates

Client-side gates observed in the binary (return type decides the hook's Swift
signature — a mismatch crashes):

`BOOL`: `LINAuthConfigurationManager -isPremiumSubscriber`,
`LINFeedHeaderPresenterStyle -shouldDisplayPremiumBar` / `-shouldDisplayPremiumLogoV2`,
`LINEntityCardData -isPremium`, `LINLEIADashboardConfig -isPremium`.

`NSNumber`: `PremiumFeatureAccess -canViewWVMP / -canBrowseProfiles /
-canViewJobAnalytics / -canViewCompanyInsights / -canAccessLearningVideos`,
`DashFeatureAccess -hasAccess`, `DashProfile -premium` /
`-showPremiumSubscriberBadge`, `Me -premiumSubscriber`.

These expose client UI. Who-viewed-me lists, InMail and Learning streams are
server-enforced and come back empty regardless.

## Open questions (need a live pass on the current build)

- Exact `tabName` strings returned by `mainNavTabsOrder` (case/spelling) — the
  reorder hook publishes them at runtime to `lproTabBar.discoveredTabs`.
- Whether returning a shorter tab array is honored by
  `sanitizedTabControllerViewControllers:` without a crash.
- The real markers of suggestion/promo cards that survive the phrase list.
- Whether the social-proof line always sits in the top 80 pt (comment and repost
  wording included).
