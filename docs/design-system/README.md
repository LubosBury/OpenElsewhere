# Handoff: OpenElsewhere — App Store build UI redesign

## Overview

The sandboxed (App Store) build of **OpenElsewhere** shows too much at once. In the worst case `SettingsView` stacks a header card carrying four controls, then up to **three** setup banners (`statusBanner`, `automationPermissionBanner`, `profileHelperCard`), then a card holding a single picker, then the rules card — all in one scrolling column. Several buttons also misdescribe what they do under the sandbox.

This redesign reorganises the same functionality into a tabbed window where **only one setup task is visible at a time**, moves first-run setup into a short onboarding flow, and rewrites rules as readable sentences.

Nothing here changes routing behaviour, `RoutingEngine`, `BrowserLauncher`, or `Capabilities`. It is a view-layer redesign.

## About the design files

`design/AppStoreRedesign.dc.html` is a **design reference written in HTML**, not production code. It is an interactive prototype that shows intended layout, spacing, colour, type, and behaviour.

The target codebase is **SwiftUI (macOS 14+)**, at `LubosBury/OpenElsewhere`, `OpenElsewhere/Sources/`. Recreate these designs in SwiftUI using the app's existing patterns (`@EnvironmentObject var routingEngine`, `Capabilities` booleans, the `glassCard()` modifier) — do not port HTML or introduce a web view.

To view the prototype, open `design/AppStoreRedesign.dc.html` in a browser. It ships with the design system's token CSS in the same folder.

## Fidelity

**High fidelity.** Colours, type, spacing, radii, and shadows are exact and are all expressed as tokens (see *Design tokens*). The prototype's rounded-rect radii, hairline borders, and material blurs map 1:1 onto SwiftUI's `RoundedRectangle(cornerRadius:style:.continuous)`, `strokeBorder`, and `.regularMaterial` / `.ultraThinMaterial`.

Two deliberate deviations from a literal read of the prototype:

1. **App monograms** — the prototype draws a lettered accent tile per source app because a browser can't read macOS app icons. In the app, keep using the real icon: `NSWorkspace.shared.icon(forFile:)`, 16–18 pt.
2. **Fonts** — the prototype uses JetBrains Mono + IBM Plex Sans as stand-ins for the system faces. In SwiftUI use `.system(design: .rounded)` where the prototype uses the mono/label face (headings, tab labels, uppercase eyebrows, keyboard hints), and the default system face for body copy.

---

## Screens / views

### 1. Settings window

**Purpose:** all configuration, in three tabs, at `minWidth: 620`.

**Structure, top to bottom:**

| Region | Height / padding | Contents |
|---|---|---|
| Header | `.padding(20)`, no card of its own | App icon tile (44×44, radius 16, `.ultraThinMaterial`, accent hairline) · title `17pt semibold rounded` · subtitle `12pt secondary` · spacer · master switch |
| Tab bar | `.padding(.horizontal, 20)`, 2 pt gap | Three segments: **General · Rules · About** |
| Divider | hairline, full width | |
| Content | `.padding(20)`, min height ≈ 290 | Setup strip (if any) + active tab |

**Header changes from today:**
- The **Buy Me a Coffee / tip menu is removed from the header** and lives in the About tab. This also resolves the `Capabilities.showsExternalDonationLink` branch cleanly: the header is identical in both builds; only the About tab differs.
- The master `Toggle` gains a label: uppercase `ROUTING` in accent when on, `PAUSED` in tertiary when off, 10 pt tracked. The whole label+switch is one hit target.
- The switch shows an accent glow when on (`0 0 26px` accent at 35% — see `--glow-accent`).

**Tab bar:** segments are plain buttons, 11 pt uppercase tracked (`0.06em`), padding `8×14`, radius 10. Active = `--surface-card-raised` fill + primary text. Inactive = transparent + tertiary text. No underline, no bottom border.

Default tab on open: **Rules**. (It is what users come back for; General is set once.)

---

### 2. The setup strip — the core change

Today three banners can appear simultaneously. Replace with a **priority queue that renders exactly one item**, at the top of the content area, on every tab.

Priority order:

| # | Condition | Tone | Title | Body | CTA |
|---|---|---|---|---|---|
| 1 | `!isHandlingLinks` | accent | "OpenElsewhere isn't handling links yet" | "macOS won't let a sandboxed app claim this itself — pick OpenElsewhere under \"Default web browser\"." | **Open System Settings** |
| 2 | `automationPermissionDenied` | warn (orange) | "Let it control Arc and Dia" | "Without automation permission, links open a new popup window instead of a tab in the window you already have." | **Open Privacy Settings** |
| 3 | `Capabilities.usesScriptBasedProfileRouting && !profileHelperInstalled` | accent | "Route to a specific profile" | "Optional. Profile routing needs a small helper script you install once — the sandbox blocks the app from doing it." | **Show me how** |

Below the CTA, right-aligned, 10 pt tertiary: `"\(remaining) more after this"`, or `"Last step"` when it is the only one.

**Layout:** `HStack(spacing: 14)`, `.padding(.horizontal, 16).padding(.vertical, 14)`, radius 16, fill = tone tint, `strokeBorder` = tone line at 0.5 pt. Leading 32×32 glyph tile (radius 10, same tint + line, tone-coloured SF Symbol): `bolt.horizontal.circle.fill`, `lock.shield.fill`, `person.2.badge.gearshape` respectively. Then a `VStack(alignment: .leading, spacing: 2)` with 13 pt semibold title and 11.5 pt secondary body (`.fixedSize(horizontal: false, vertical: true)`).

**CTA button:** filled with the tone colour, `text-on-accent` label (navy on accent, navy on orange), 11 pt semibold tracked, padding `8×14`, radius 10, tone glow.

**Entry/exit:** `.transition(.opacity.combined(with: .move(edge: .top)))` with `.spring(response: 0.4, dampingFraction: 0.8)` — the prototype's `oe-rise` keyframe (6 px rise + fade, 400 ms).

**Naming note:** the App Store build's "Make it Default" button never sets the default — it opens System Settings. The redesign labels it for what it does. Keep `Capabilities.canSetDefaultBrowser` driving the label so the Developer ID build still reads "Make it Default".

**Item 3 — the helper script.** Today it exposes three buttons (`Copy Script`, `Open Folder`, `Check Again`) inline. Replace with a single **Show me how** that opens a sheet holding those three actions plus the `chmod +x` instruction. *The sheet is not designed yet* — see *Open questions*.

---

### 3. General tab

Two rows, each `.padding(.horizontal, 16).padding(.vertical, 14)`, radius 12, fill `--surface-inset`, hairline `--border-inset`, 10 pt gap between them. Above them an uppercase 10 pt tertiary eyebrow: **FALLBACK**.

1. **Default browser** — 13 pt medium title, 11.5 pt secondary subtitle "Used when no rule matches the app a link came from." Trailing: a single picker whose entries are **browser + profile combined** (see *Rules*). Replaces the whole `defaultBrowserCard`, including its separate profile picker.
2. **Launch at login** — "Keep routing after a restart." Trailing: switch. *(New. Ship only if `SMAppService.mainApp` is wired up; otherwise omit the row.)*

---

### 4. Rules tab

Header row: eyebrow **ROUTING RULES** (10 pt uppercase tertiary) + trailing **+ Add rule** button (accent-soft fill, accent hairline, accent label, 11 pt semibold tracked, padding `7×13`, radius 10).

**Rule row** — replaces `RuleCard`. `HStack(spacing: 8)`, padding `12×11`, radius 12, fill `--surface-inset`, hairline. It reads as a sentence:

> `[icon]` Links from `[Slack ▾]` open in `[Arc · Work ▾]` ⟶ `✕`

- "Links from" and "open in" are 13 pt secondary connective text.
- Pickers are 13 pt medium, `--surface-control` fill, hairline, radius 8, padding `10×5` — visually lighter than today's `.controlSize(.large)` pickers.
- The **arrow glyph is gone**; the sentence carries direction.
- **The profile picker is folded into the destination picker.** One menu lists browsers and their profiles as combined entries: `Safari`, `Arc`, `Arc · Work`, `Google Chrome`, `Google Chrome · Personal`, … Build it from `browsers` × `ProfileDiscovery.profiles(forBrowser:)`; a browser with no profiles contributes one entry. Selecting an entry sets `targetBrowserBundleID` and `profileDirectoryName` together. This removes the conditional third picker and the row-width jitter it caused.
- Delete is a trailing `✕` (`xmark`), tertiary, that tints `--status-danger` on hover, `.buttonStyle(.borderless)`.

Keep the existing insert/remove spring transitions.

**Empty state:** dashed hairline container, radius 12, `.padding(.vertical, 38)`, centred: app icon at 40 pt / 50% opacity with a soft accent glow, "No rules yet" (13 pt semibold), then 11.5 pt secondary, max 280 pt wide: *"Every link goes to \(fallback). Add a rule to send links from one app somewhere else."* — it names the current fallback rather than stating an abstraction. Below, an **Add your first rule** button (accent-soft, glowing).

---

### 5. About tab

Two rows in the same style as General, then a link row.

1. **OpenElsewhere 1.2 (App Store)** / "Sandboxed build · profile routing via helper script" · trailing link **Release notes**.
2. **Tip jar** — title is `tipJar.didTip ? "Thank you — that genuinely helps." : "Leave a tip"`, subtitle "One-off, no unlocks. Thank you either way." Trailing: **three price buttons side by side**, one per `TipJar.products` in ascending price order, showing `product.displayPrice`. Style: `rgba(255,214,10,0.16)` fill, `rgba(255,214,10,0.35)` hairline, primary label, 11 pt semibold, padding `11×7`, radius 9. Disabled while `tipJar.isPurchasing`. If `products.isEmpty` (offline, or products unapproved), hide the whole row rather than showing "Loading…".
   - **Developer ID build:** replace the three buttons with the existing single Buy Me a Coffee `Link`, same row, same styling.
3. **Links row:** Privacy · Source on GitHub · Support — 11.5 pt, accent, `.padding(.horizontal, 16)`, 18 pt gap.

---

### 6. First-run onboarding

A 420 pt window shown once, before Settings, so Settings opens clean. Centred `VStack`, `.padding(.top, 34).padding(.horizontal, 30).padding(.bottom, 26)`, 12 pt spacing:

- App icon in a 64×64 tile, radius 20, `.ultraThinMaterial`, accent hairline, strong accent glow.
- Title 18 pt semibold rounded; body 12.5 pt secondary, max 300 pt, centred.
- Primary button: filled accent, `text-on-accent`, 12 pt semibold tracked, padding `20×10`, radius 10, accent glow.
- Below it a tertiary 11.5 pt text button: **Skip for now**.
- Three 6 pt progress dots, 6 pt gap; active = accent + glow, inactive = `--border-hairline`.

Steps mirror the setup queue:

| # | Title | Body | CTA |
|---|---|---|---|
| 1 | Make it your link handler | "Other apps need to send URLs here first. macOS asks you to confirm in System Settings." | Open System Settings |
| 2 | Allow control of your browsers | "So a link becomes a tab in the window you already have, not another popup." | Open Privacy Settings |
| 3 | Send your first link somewhere | "Pick one app to route differently. You can change it any time." | Add a rule |

Steps already satisfied are skipped. Step 3's CTA closes onboarding, opens Settings on the Rules tab, and calls `addEmptyRule()`. Skipping any step leaves it in the Settings setup queue — the two share one source of truth.

Persist completion in `@AppStorage("hasCompletedOnboarding")`.

---

### 7. Menu-bar panel

Structurally unchanged from `MenuBarView`; restyled to the glass panel and sharing the rule sentence. Width 320, radius 16, `.padding(6)`, fill `--surface-menu`, `blur(40px) saturate(150%)`, hairline, `--shadow-menu`.

- Toggle row: "Route links" + a 36×22 switch (17 pt knob, 14 pt travel), padding `10×9`, radius 9.
- Hairline divider, `.padding(.horizontal, 8)`, 5 pt vertical margin.
- One row per rule: 18×18 app icon (radius 5) · source name · tertiary `→` · destination in secondary. 12.5 pt, padding `10×8`, hover fill `--surface-control`.
- Empty: "No rules — everything opens in \(fallback)", 12 pt tertiary.
- Divider, then **Settings…** `⌘,` and **Quit OpenElsewhere** `⌘Q`, shortcut glyphs right-aligned in 11 pt tertiary mono.

**Implementation caveat:** `.menuBarExtraStyle(.menu)` renders each top-level view as an `NSMenuItem`, which is why today's code folds each rule into a single interpolated `Text`. This panel needs `.menuBarExtraStyle(.window)`. That is a real behavioural change — the panel stops being a system menu and becomes a popover you must dismiss. Confirm before switching; if `.menu` must stay, keep today's `Text` interpolation and take only the copy changes.

---

## Interactions & behaviour

- **Tab switch** — instant, no crossfade. Content height is stable (min 290) so the window doesn't jump.
- **Master switch** — `.spring(response: 0.4, dampingFraction: 0.8)` on the knob; track colour animates over 200 ms ease-out. When off, the app keeps its default-handler status but passes links straight through; the setup strip is unaffected.
- **Setup strip advance** — resolving item *n* animates it out and the next in with the same spring. Re-evaluate the queue on `NSApplication.didBecomeActiveNotification` (as today, hopping to the next main-actor turn before touching `@State`).
- **Rule add** — new row springs in at the bottom, source defaults to the first app not already used, destination to the current fallback.
- **Rule delete** — immediate, no confirmation, springs out.
- **Hover** — menu rows and the delete button only. Buttons use the standard SwiftUI press state.
- **Empty state** appears whenever `rules.isEmpty`, in both the Rules tab and the menu panel.

## State

Existing, unchanged: `routingEngine.isEnabled`, `.rules`, `.defaultBrowserBundleID`, `.defaultProfileDirectoryName`; `isHandlingLinks`, `automationPermissionDenied` (`@AppStorage`), `profileHelperInstalled`, `browsers`, `allApps`, `profileCache`, `tipJar`.

New:
- `selectedTab: Tab` — `.general` / `.rules` / `.about`, default `.rules`. `@SceneStorage` so it survives a window close.
- `hasCompletedOnboarding: Bool` — `@AppStorage`.
- `onboardingStep: Int`.
- `launchAtLogin: Bool` — only if `SMAppService` is wired.
- `showsHelperSheet: Bool`.

Derived: `setupQueue: [SetupItem]` — computed from the three existing conditions in priority order; the strip renders `.first`, onboarding walks the whole list.

## Design tokens

Exact values, as used in the prototype. Dark theme is canonical.

**Colour**
```
navy-1000 #070B1A   navy-900 #0D142E   navy-800 #141F47
accent (dark)  #73AEFF        accent (light) #3373F2
accent-soft    rgba(115,174,255,0.18)
accent-line    rgba(115,174,255,0.35)
warn           #FF9F0A        warn tint rgba(255,159,10,0.16)  warn line rgba(255,159,10,0.38)
danger         #FF6B6B        ok #32D6A0        sponsor #FFD60A
text-primary   rgba(255,255,255,0.95)
text-secondary rgba(255,255,255,0.60)
text-tertiary  rgba(255,255,255,0.38)
text-on-accent #070B1A
surface-card        rgba(255,255,255,0.07)
surface-card-raised rgba(255,255,255,0.10)
surface-inset       rgba(255,255,255,0.05)
surface-control     rgba(255,255,255,0.08)
surface-menu        rgba(18,24,48,0.72)
border-hairline rgba(255,255,255,0.10)   border-inset rgba(255,255,255,0.08)
window background: linear-gradient(135°, #0D142E → #141F47)
```
Light-theme overrides are in `design/colors.css` under `:root[data-theme="light"]`.

**Type** (prototype face → SwiftUI)
```
window title      11 pt, tracking 0.06em, secondary      → .system(size:11, design:.rounded)
app name          17 pt semibold, tracking -0.01em       → .system(size:17, weight:.semibold, design:.rounded)
app subtitle      12 pt, secondary                       → .callout
tab label         11 pt, uppercase, tracking 0.06em      → .system(size:11, design:.rounded)
eyebrow           10 pt, uppercase, tracking 0.14em, tertiary
row title         13 pt medium
row subtitle      11.5 pt secondary, line-height 1.45
banner title      13 pt semibold
button label      11–12 pt semibold, tracking 0.06em
menu row          12.5 pt
```

**Spacing / radii**
```
window padding 20 · card gap 20 · banner padding 16 · row padding 14×10
radius: chip 10 · row 12 · tile 16 · banner 16 · card 20 · pill 999
hairline 0.5 pt
window minWidth 620 (prototype frame 680) · menu width 320
```

**Effects**
```
blur ultra-thin  blur(20px) saturate(160%)   → .ultraThinMaterial
blur regular     blur(32px) saturate(180%)   → .regularMaterial
blur menu        blur(40px) saturate(150%)
shadow-card  0 8px 20px rgba(0,0,0,0.30)
shadow-menu  0 16px 48px rgba(0,0,0,0.45)
glow-accent  0 0 24px rgba(115,174,255,0.45)
glow-inset   inset 0 1px 0 rgba(255,255,255,0.14)
spring       cubic-bezier(0.34,1.36,0.64,1)  ≈ .spring(response:0.4, dampingFraction:0.8)
ease-out     cubic-bezier(0.2,0.8,0.2,1) · fast 120ms · base 200ms · spring 400ms
```

The prototype exposes `glowLevel` as a multiplier (default 55%, reviewed at 50%). Glow radii above are at 100% — scale them by ~0.5 to match what was approved, or drop glow entirely on non-focused elements if it reads as heavy on a real display.

## Assets

- App icon: already in the repo at `OpenElsewhere/Resources/Assets.xcassets/AppIcon.appiconset`. The prototype uses copies of the 128/256 px renditions.
- Icons: SF Symbols throughout — `bolt.horizontal.circle.fill`, `lock.shield.fill`, `person.2.badge.gearshape`, `xmark`, `plus`. The prototype substitutes text glyphs because SF Symbols aren't available in a browser.
- App icons per rule: `NSWorkspace.shared.icon(forFile:)` at runtime.
- No new assets are required.

## Files in this bundle

```
design/AppStoreRedesign.dc.html   the prototype — open in a browser
design/styles.css                 token entry point
design/colors.css  typography.css  spacing.css  effects.css  fonts.css
design/ds-base.js                 loads the stylesheets (flattened for this bundle)
```

Source of truth in the design system project: `templates/appstore-redesign/AppStoreRedesign.dc.html`.

Files to change in the app: `OpenElsewhere/Sources/SettingsView.swift` (largest), `MenuBarView.swift`, `OpenElsewhereApp.swift` (onboarding window + scene storage). `Capabilities.swift`, `RoutingEngine.swift`, `BrowserLauncher.swift`, and `TipJar.swift` should not need behavioural changes.

## Open questions

1. **Helper-script sheet** — the "Show me how" destination isn't designed. It needs the three existing actions (Copy Script, Open Folder, Check Again) plus the `chmod +x` line.
2. **`.menuBarExtraStyle(.window)`** — required for the redesigned panel; changes menu dismissal behaviour. Needs a decision.
3. **Launch at login** — new row, only if `SMAppService` is adopted.
4. **Light mode** — tokens exist, no screens designed. The prototype is dark-only.
