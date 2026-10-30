# AGENTS.md — LinkedIn Professional

Guidance for any agent working in this repo. The global rules in the user's
`CLAUDE.md` still apply (no Claude attribution on commits/PRs; describe what a
change **does**, never claim it "works"/"is verified"; commit on `main`; build in
a terminal, not the sandbox; version is `<patch>.b<build>` and `b<build>` only
increases). This file adds the **settings design and language policy** — hold
every settings screen to it, so the whole surface reads as one modern, clean app.

## Settings — layout

- Native SwiftUI in a `List` with `.listStyle(.insetGrouped)`. Group related
  controls into `Section`s; let the inset-grouped spacing breathe — do not cram
  unrelated controls into one section.
- Every `Section` gets a short **noun-phrase header** (`"Bottom bar"`,
  `"Surfaced by your network"`, `"This session"`). Add a **footer** whenever one
  sentence would explain what the controls do or their honest limit — footers are
  the norm, not the exception.
- Every toggle / list row is a `Label(_, systemImage:)` with a fitting SF Symbol.
  No bare-text rows next to labelled ones — keep a screen visually consistent.
- The top screen (`LProSettingsView`) opens with a **Liquid Glass header card**
  (`LProGlassCard`: `glassEffect` on iOS 26+, a rounded fill below) and lists
  features as rows with a **tinted rounded icon tile** (`LProIconTile`), a title,
  a one-line subtitle and a disclosure chevron.
- This flow has **no SwiftUI `NavigationStack`** (the view is hosted in a
  `UIHostingController` on a UIKit nav). Push sub-screens through the UIKit `push`
  closure, not `NavigationLink`; use `.pickerStyle(.menu)` (a default
  `.navigationLink` picker needs a stack it hasn't got).

## Settings — language

- **Sentence case** for row labels and footers ("Hide sponsored posts", not
  "Hide Sponsored Posts"). Section/screen titles are short noun phrases.
- Row labels are **concise and action-first**: "Hide …", "Force …", "Skip …",
  "Open on launch". No trailing punctuation.
- **Footers are one sentence**: say what the control does, and — when it matters —
  the honest limit, with quoted UI strings in curly quotes. Example:
  "A category that stays at zero may mean its marker changed in this LinkedIn
  build." Use `—` (em dash) and `"…"` (curly quotes), as the existing copy does.
- **State scope honestly.** A premium flag says "Takes effect on-device" when a
  local hook delivers it, or "Entry/UI only — LinkedIn serves the data" when the
  client only reveals an entry point. Never imply server-gated data is unlocked.
- Describe behaviour, never assert it works. "Flips the opt-out so the system
  renders the floating glass bar" — not "makes the glass bar work".

## Settings — tone

Direct, technical, honest. No marketing voice, no emoji in UI copy. The reader is
a power user who wants to know exactly what each control changes and what it
cannot do.

## Reference

`LProFeedSettingsView` is the canonical example of the structure above (grouped
sections, descriptive footers, symbol labels, a live-stats section). New settings
screens should read like it.
