# LinkedIn Professional

A customization tweak for the native **LinkedIn iOS** app (`com.linkedin.LinkedIn`),
written in **Swift + [Orion](https://orion.theos.dev)**. Installs on **jailbreak**
(`.deb`) and via **sideload / AltStore** (injected `.ipa`). Built to be modular and
**version-independent** — every hook targets LinkedIn's classes by runtime name,
guarded by presence checks, with no hardcoded offsets.

> Early scaffold. The infrastructure below is in place; the user-facing features
> land per phase (see *Roadmap*). Each build is compiled with Theos and exercised
> on-device — nothing here is asserted to work without that.

## Planned features

- **Settings** — a LinkedIn Professional row placed **above** LinkedIn's own
  Settings, opening a separate Apple-native (SwiftUI) settings screen: native
  Liquid Glass on iOS 26/27, standard UIKit styling on iOS 18–25.
- **Feed filtering** — hide posts surfaced only because someone reacted, filterable
  by reaction type (like / celebrate / support / love / insightful / funny), applied
  at the Voyager data layer so it survives UI redesigns.
- **Bottom nav bar** — native Liquid Glass on iOS 26/27 (adapting LinkedIn's own
  tab bar) and a customizable restyle (reorder / hide / relabel tabs) on iOS 18–25.
- …and more, on the modular base below.

## Architecture

- `Sources/LinkedInPro/Core` — the version-independence layer: `LinkedInVersion`
  (date-style version gate), `HookRegistry` (activates each feature's Orion
  `HookGroup` only after its target classes resolve), `LProLog`.
- `Sources/LinkedInPro/{Settings,Feed,NavBar}` — feature modules (per phase).
- `Sources/LinkedInPro/DevKit` — the on-device **Striker** console, dev-gated.
- `Sources/LinkedInProC` — the Orion bootstrap (`Tweak.m`).
- Shared infrastructure is consumed as submodules, not copied:
  - [`striker`](https://github.com/RobyRew/striker) — USB-driven runtime console.
  - [`tweak-kit`](https://github.com/RobyRew/tweak-kit) — sideload fix
    (`zxPluginsInject`), RE inventory, and shared Swift helpers (`@UserDefault`,
    `WindowHelper`, `TweakLog`, `HookActivator`).

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
produced by the GitHub Actions workflow; it takes the vanilla **decrypted** IPA as
a build-time input (see below).

## DevKit (Striker)

Dev builds embed the Striker console. Arm it with `-DLPRO_DEVKIT`, a
`LPRO_DEVKIT` marker file in the app's Documents, or the hidden
`lproDevKitEnabled` setting. Then, over USB:

```bash
iproxy 45801 45801
Submodules/striker/driver/striker.py uitree
```

## Legal

This repository contains **only original tweak source**. It does **not** contain,
and must not be used to distribute, LinkedIn's app binary. CI takes a decrypted
IPA as a build-time input; it is never committed here. LinkedIn is a trademark of
its owner; this project is unaffiliated.

## Roadmap

Phase 0 scaffold + DevKit · Phase 1 settings entry + SwiftUI shell · Phase 2 feed
filter · Phase 3 nav bar · Phase 4 polish + more features.

## License

GPL-3.0. See [LICENSE](LICENSE).
