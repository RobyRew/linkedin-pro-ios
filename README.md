# LinkedIn Professional

A customization tweak for the native **LinkedIn iOS** app (`com.linkedin.LinkedIn`),
written in **Swift + [Orion](https://orion.theos.dev)**. It installs on **jailbreak**
(`.deb`) and via **sideload / AltStore** (injected `.ipa`), and it is built to be
modular and **version-independent**: every hook targets LinkedIn's classes by
runtime name, guarded by presence checks, with no hardcoded offsets. A selector
LinkedIn renames on a new build degrades one feature instead of crashing the app
(a non-fatal Orion `handleError`).

> Each build is compiled with Theos and exercised on-device over USB (Striker,
> below). This README describes what the code **does**, not a guarantee of any
> outcome on a given LinkedIn build — LinkedIn's app changes server-side and
> client-side, so verify on the build you run.

## Features

- **Settings entry** — a *LinkedIn Professional* row placed in the Me-tab account
  panel, above *Settings & Privacy*, opening a separate Apple-native (SwiftUI)
  settings screen. It can also be opened by long-pressing the first tab.
- **Feed filtering** (opt-in) — hides posts surfaced only because a connection
  **reacted** (per reaction type: like / celebrate / love / support / insightful /
  funny), **commented**, or **reposted**. The main feed is SDUI, so its cards are
  collapsed at the collection-view data source (height 0, no gap); other feed
  surfaces are filtered at the Voyager data layer.
- **Ads & sponsored** (on by default) — hides *Promoted* / *Sponsored* cards and
  suggestion/promo chrome app-wide, and Premium upsell banners. Done with one
  shared, coalesced, bounded view sweep keyed on the visible text / accessibility
  label (version-independent).
- **Premium (client spoof)** — flips the client's premium gates so premium **UI**
  surfaces: the gold badge, premium bars and logos, suppressed upgrade prompts and
  interstitials, and premium entry points. Per-surface flags let each be turned on
  or off. **Scope is honest:** LinkedIn enforces the actual premium *data* on its
  servers, so who-viewed-me lists, analytics, InMail credits and Learning streams
  stay gated — this unlocks client-gated UI, not server data. Each flag in the
  panel states whether it takes effect on-device or is entry/UI only.
- **Navigation bar** — reorder, hide and relabel tabs; icon-only mode; a chosen
  launch tab; a dark-only tab bar; and a toggle that flips LinkedIn's iOS 26/27
  Liquid-Glass design opt-out. Reorder/hide apply live via the modern `UITab` API
  on iOS 18+ (preserving tab identity), or a `viewControllers` rebuild otherwise.
- **DevKit (Striker)** — an on-device Objective-C runtime console for RE, reachable
  over a USB-forwarded loopback port. Dev-gated (see below).

## Installing

- **Sideload (`.ipa`)** — the GitHub Actions workflow injects the tweak into a
  **decrypted** LinkedIn IPA (provided as a build-time input — never committed
  here) with cyan + `zxPluginsInject`, and publishes an AltStore source. Add the
  source to AltStore / SideStore, or install the `.ipa` with Sideloadly.
- **Jailbreak (`.deb`)** — install the rootless or RootHide `.deb` from the
  release and respring.

Open the settings from the Me tab (the row above *Settings & Privacy*) or by
long-pressing the first tab.

## Building

Requires [Theos](https://theos.dev) with Orion. Clone with submodules, then build
**in a terminal** (Orion's codegen uses atomic writes that some sandboxes deny):

```bash
git clone --recursive https://github.com/RobyRew/linkedin-pro-ios
cd linkedin-pro-ios
THEOS_PACKAGE_SCHEME=rootless make package FINALPACKAGE=1   # rootless jailbreak .deb
# THEOS_PACKAGE_SCHEME=roothide make package FINALPACKAGE=1 # RootHide .deb
```

The sideload `.ipa` (cyan injection + `zxPluginsInject` + AltStore source) is
produced by the GitHub Actions workflow; it takes the vanilla decrypted IPA as a
build-time input.

## Architecture

- `Sources/LinkedInPro/Core` — version-independence layer: `LinkedInVersion`
  (date-style version gate), `HookRegistry` (activates each feature's Orion
  `HookGroup` only after its target classes resolve), `LProLog`, `LProViewSweeper`
  (the shared bounded ad/upsell sweep).
- `Sources/LinkedInPro/{Settings,Feed,Ads,NavBar,Premium}` — feature modules.
- `Sources/LinkedInPro/DevKit` — the on-device **Striker** console, dev-gated.
- `Sources/LinkedInProC` — the Orion bootstrap (`Tweak.m`).
- Shared infrastructure is consumed as submodules, not copied:
  - [`striker`](https://github.com/RobyRew/striker) — USB-driven runtime console.
  - [`tweak-kit`](https://github.com/RobyRew/tweak-kit) — sideload fix
    (`zxPluginsInject`), RE inventory, and shared Swift helpers (`@UserDefault`,
    `WindowHelper`, `TweakLog`, `HookActivator`).

## DevKit (Striker)

Dev builds embed the Striker console. It is armed by `-DLPRO_DEVKIT`, a
`LPRO_DEVKIT` marker file in the app's Documents directory, or the hidden
`lproDevKitEnabled` setting (the absent key defaults on). It listens on
`127.0.0.1:45801`, answers only while LinkedIn is foregrounded, and re-arms itself
on every foreground. Over USB:

```bash
iproxy 45801 45801
STRIKER_PORT=45801 python3 Submodules/striker/driver/striker.py "uitree 80 20000"
```

Useful commands: `uivc`, `uitree [depth] [nodes]`, `uidump`, `classes <filter>`,
`methods <Class>`, `obj <addr>`, `sendq <obj> <sel>`.

## Reverse-engineering notes

These record what exists in the examined build; they do not assert that a feature
works. Full notes: [`RE-NOTES.md`](RE-NOTES.md),
[`PREMIUM-SURFACE.md`](PREMIUM-SURFACE.md),
[`PREMIUM-ANALYSIS.md`](PREMIUM-ANALYSIS.md).

<details>
<summary><b>Build examined</b></summary>

LinkedIn `2026.1021.1050` (`CFBundleVersion 9.32.5021`), MinimumOS 18.0, built with
the iOS 26 SDK, `UIDesignRequiresCompatibility=1` (LinkedIn opts out of the iOS 26
Liquid-Glass redesign). Fully decrypted, single-arch arm64. Inventory: ~19,008 ObjC
classes / 151,168 methods (main binary), ~14,427 classes / 131,545 methods
(VoyagerLibs). Device used: iPhone 16 Pro Max, iOS 27.

</details>

<details>
<summary><b>Navigation / tab bar</b></summary>

`LINMainNavViewController` **is** a `UITabBarController`. Tab types come from
`_TtC14HomeNavAPIImpl21MainNavTabTypeFactory` (`HomeNavAPIImpl.MainNavTabTypeFactory`),
one zero-argument method per type: `feed`, `messaging`, `myNetwork`, `jobs`,
`notifications`, `post`, `video`, `trendsHub`, `games`, `more` — plus
`mainNavTabsOrder` and `invalidateTabsOrderCache`. `post` is the center floating
action button, not a bar tab. Items: `LINTabBarItemFactory -makeTabBarItemForTabType:`.
Controllers / selection: `LINMainNavTabBarViewControllerFactory`,
`LINRootViewControllerManager -selectMainNavTab:triggeredByUserInteraction:completion:`.
The tab set is server-driven and can vary per member, so the bar already tolerates
a varying number of tabs.

</details>

<details>
<summary><b>Feed (SDUI)</b></summary>

Main feed: `VoyagerFeed.FeedSDUIViewController` → `SDUIScreenViewController` →
`SDUI.Zen.ComponentCollectionView` → cards of
`SDUI.Zen.ComponentCollectionViewDataSource.ComponentCell`. The data source's only
two `@objc` entry points are `collectionView:willDisplayCell:forItemAtIndexPath:`
and `collectionView:layout:sizeForItemAtIndexPath:`; the feed supplies explicit
item sizes, so returning height 0 collapses a card without a gap.
`DashFeedUpdateBuilder.build:error:` never sees SDUI feed cards.

Card metadata is delivered as **accessibility labels** on `SDUI.TextBlockView`, not
as `UILabel.text` — e.g. `Promoted`, `View Sponsored Content`, `<name> likes this`,
`<name> commented on this`. A post body is also an accessibility label, so the
social-proof line is distinguished by position (it sits in the top ~80 pt of the
cell).

</details>

<details>
<summary><b>Me-tab account panel</b></summary>

`HomeNav.NavPanelViewController` (a side panel, no navigation controller). The
bottom box `HomeNav.NavPanelAccountAreaView` (a11y `NavPanelViewControllerAccountAreaViewA11yID`)
is frame-positioned (~65 pt = 1 pt divider + 16 pt gap + 48 pt row) and holds a
`NavPanelDividerView` and a `NavPanelMenuItemView` (a11y
`NavPanelAccountAreaViewSettingsIconLabelView` = *Settings & Privacy*). The *LinkedIn
Professional* row is placed above this box. The "Try Premium" upsell is an
`ARTButton` re-added during layout, so hiding it is re-applied per layout pass.

</details>

<details>
<summary><b>Premium surface (client vs server)</b></summary>

Client-side gates (the return type decides the hook's Swift signature — a mismatch
crashes):

- `BOOL`: `LINAuthConfigurationManager -isPremiumSubscriber`,
  `LINFeedHeaderPresenterStyle -shouldDisplayPremiumBar` / `-shouldDisplayPremiumLogoV2`,
  `LINEntityCardData -isPremium`, `LINLEIADashboardConfig -isPremium`.
- `NSNumber`: `PremiumFeatureAccess -canViewWVMP / -canBrowseProfiles /
  -canViewJobAnalytics / -canViewCompanyInsights / -canAccessLearningVideos`,
  `DashFeatureAccess -hasAccess`, `DashProfile -premium` /
  `-showPremiumSubscriberBadge`, `Me -premiumSubscriber`.

Flipping these exposes client UI (badges, bars, entry points, suppressed upsells).
The data behind premium features is server-enforced and arrives in the
`GetPremiumFeatureAccessByAccessTypes` response and each feature's own payload, so
who-viewed-me lists, InMail credits, analytics and Learning streams stay gated for
a non-entitled member. See [`PREMIUM-SURFACE.md`](PREMIUM-SURFACE.md) for the full
access-type list and upsell-surface classes.

</details>

## Legal

This repository contains **only original tweak source**. It does **not** contain,
and must not be used to distribute, LinkedIn's app binary. CI takes a decrypted IPA
as a build-time input; it is never committed here. The reverse-engineering notes
describe interfaces present in the examined build for interoperability and research.
LinkedIn is a trademark of its owner; this project is unaffiliated.

## License

GPL-3.0. See [LICENSE](LICENSE).
