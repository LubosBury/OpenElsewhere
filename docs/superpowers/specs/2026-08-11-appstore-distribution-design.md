# OpenElsewhere — Dual-Channel Distribution Design

**Date:** 2026-08-11
**Status:** Approved, ready for implementation planning

## Goal

Publish OpenElsewhere on the Mac App Store as the primary channel, while keeping a
Developer ID–signed, notarized DMG (distributed via Homebrew cask) as a secondary
channel for power users.

The paid Apple Developer account (Team ID `78QQBJB52G`) unlocks both.

## Background

OpenElsewhere is a menu-bar utility that registers as the system default browser,
intercepts `http`/`https` open requests, and re-routes each URL to a browser and
profile chosen by a per-source-app rule.

Today it ships as an **ad-hoc signed** (`CODE_SIGN_IDENTITY: "-"`) DMG through a
personal Homebrew tap. Users must install with `--no-quarantine` or strip the
quarantine xattr by hand, because the app is neither signed nor notarized.

Three mechanisms in the current implementation are incompatible with the App
Sandbox that the Mac App Store mandates:

| Mechanism | Location | Sandbox verdict |
|---|---|---|
| `Process` → `/usr/bin/open` and direct browser-binary launch | `BrowserLauncher.swift:152`, `:254` | Blocked — cannot exec binaries outside the app bundle |
| `NSAppleScript` → Arc/Dia | `BrowserLauncher.swift:186` | Requires an apple-events exception entitlement |
| `setDefaultApplication(at:toOpenURLsWithScheme:)` | `SettingsView.swift:364` | Apple has not extended runtime default-handler APIs to sandboxed apps |
| `~/Applications` enumeration | `BrowserDiscovery.swift:32` | Home directory redirects to the sandbox container |

Precedent: **Velja** (Sindre Sorhus) is the same app category, is sandboxed, ships
on the Mac App Store, and supports Chromium and Firefox profile routing. It also
documents that it *cannot* set itself as the default browser. Velja establishes
that the core product is achievable under sandbox; its documented limitations
define the ceiling.

## Accepted feature losses (App Store build only)

1. **One-click "Set as default browser."** Replaced by a deep link into System
   Settings. Two clicks instead of one.
2. **Apps installed only in `~/Applications` and never launched** disappear from
   the rule-source picker.
3. **The Buy Me a Coffee link**, replaced by an IAP tip jar (App Review restricts
   donation links for individuals).

Explicitly **not** a loss: per-app routing rules, Chromium/Firefox profile
selection, Arc/Dia new-tab behavior, browser discovery.

## Architecture

### One target, two configurations

A single XcodeGen target. The app binary is functionally identical across
channels; only signing, sandboxing, and one compile-time flag differ.

| | `Release` (DMG) | `ReleaseAppStore` (MAS) |
|---|---|---|
| Signing identity | Developer ID Application | Apple Distribution |
| App Sandbox | off | on |
| Hardened runtime | on | on |
| Entitlements | `OpenElsewhere.entitlements` | `OpenElsewhere-AppStore.entitlements` |
| Swift flag | — | `-D APP_STORE` |

Bundle ID stays `com.openelsewhere.app` for both, so the two builds replace rather
than duplicate one another and only one app registers as the default handler.

Preference migration between channels is **out of scope** — there is a single
user, who accepts re-entering rules if the sandbox container does not inherit
existing preferences.

### App Store entitlements

```xml
<key>com.apple.security.app-sandbox</key><true/>
<key>com.apple.security.network.client</key><true/>
<key>com.apple.security.automation.apple-events</key><true/>
<key>com.apple.security.temporary-exception.apple-events</key>
<array>
  <string>company.thebrowser.Browser</string>
  <string>company.thebrowser.dia</string>
</array>
```

`network.client` is required by StoreKit and fails at runtime, not build time, if
omitted.

`Info.plist` also gains `ITSAppUsesNonExemptEncryption = false`. OpenElsewhere
uses no encryption beyond what Apple's own frameworks provide; declaring this in
the bundle avoids being asked the export-compliance question on every upload.

The temporary exception is the single largest review risk in this plan. It
requires written justification in App Review notes.

### The `Capabilities` enum

A new ~20-line file is the **only** place `#if APP_STORE` appears. Every other
call site reads a boolean.

```swift
enum Capabilities {
    static let canSetDefaultBrowser: Bool
    static let canEnumerateUserApplications: Bool
    static let canSpawnProcesses: Bool
    static let showsExternalDonationLink: Bool
}
```

### `BrowserLauncher` rewrite

`Process` is removed from the shared path; `NSWorkspace.openApplication` replaces
it. `knownScriptingNames`, `isStrictSingleInstance`,
`sanitizeForAppleScriptLiteral`, and the profile-arg helpers are unchanged.

| Browser family | New strategy |
|---|---|
| Chromium + profile | `openApplication` with `createsNewApplicationInstance = true`, `arguments: ["--profile-directory=X", url]` — relies on the same singleton-IPC forwarding as today, via a sandbox-legal route |
| Firefox + profile | Same, `arguments: ["-P", profile, "--new-tab", url]` |
| Arc / Dia | Unchanged `NSAppleScript`; fallback becomes `NSWorkspace.open` |
| Safari / unknown | `NSWorkspace.open(url, withApplicationAt:)` |

**Structural change:** `Process.run()` is synchronous and throwing;
`openApplication` is asynchronous. `BrowserLauncher.open` becomes `async` and
`AppDelegate.dispatch` wraps it in a `Task`, rather than nesting three completion
handlers for the fallback cascade.

**`canSpawnProcesses` contingency:** if `configuration.arguments` proves
unreliable for profile switching, the DMG build retains the proven `Process` path
while the App Store build degrades to opening the browser without profile
selection. An `NSWorkspace` weakness then costs App Store users a feature rather
than costing DMG users one.

### UI changes

**Default-browser card.** With `canSetDefaultBrowser == false`, `SettingsView`
replaces the action button with an instruction card whose button opens the
relevant pane directly:

```swift
NSWorkspace.shared.open(URL(string:
  "x-apple.systempreferences:com.apple.Desktop-Settings.extension")!)
```

`checkIfDefault()` works under sandbox, so the card polls on window activation and
flips to a confirmed state once the user completes the change.

**App discovery.** `installedApps()` unions the directory scan with
`NSWorkspace.shared.runningApplications`, which is sandbox-legal. Running apps
appear regardless of install location, recovering most `~/Applications` coverage.
Applied to **both** builds — it is an improvement, not merely a sandbox patch.

### Tip jar

StoreKit 2, **consumable** products (`tip.small`, `tip.medium`, `tip.large`) —
repeatable, and carrying no "Restore Purchases" obligation. New `TipJar.swift`,
approximately 80 lines: `Product.products(for:)`, `purchase()`, verify,
`transaction.finish()`. Nothing is unlocked, so no entitlement state is persisted.

A `Products.storekit` configuration file enables local purchase testing in Xcode
before the App Store Connect products go live.

## Release pipelines

### App Store — manual

`scripts/build-appstore.sh` performs only the mechanical steps: `xcodegen
generate`, `xcodebuild archive` with the `ReleaseAppStore` configuration, then
opens the archive in Xcode Organizer. Distribution proceeds through **Distribute
App → App Store Connect**, which provides the validation UI and generates the
installer certificate automatically.

### DMG — GitHub Actions

`.github/workflows/release.yml`, triggered on `v*` tags, on a macOS runner:

1. Import the Developer ID certificate into a temporary keychain
2. `xcodegen generate` → `xcodebuild archive` (`Release`) → export
3. `create-dmg`
4. `xcrun notarytool submit --wait` → `xcrun stapler staple`
5. `gh release create` with the DMG attached
6. Emit the SHA256 to the job summary

Six repository secrets, authenticating with an App Store Connect API key rather
than an app-specific password:

`DEVELOPER_ID_CERT_P12_BASE64`, `CERT_PASSWORD`, `KEYCHAIN_PASSWORD`,
`ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8_BASE64`

The Homebrew tap bump stays manual — the SHA256 is pasted from the job summary.
Wiring a cross-repo token is not justified for a single-maintainer project.

### Documentation

- `Casks/openelsewhere.rb` — remove the entire unsigned/`--no-quarantine` caveat
  block; retain the Apple Events caveat
- `README.md` — install instruction becomes plain `brew install --cask openelsewhere`
- `RELEASING.md` — rewritten to cover both channels
- `docs/APPSTORE-SETUP.md` — new one-time manual runbook

## Verification

No test target exists, and AppKit/LaunchServices integration behavior is not
meaningfully unit-testable. Verification is a written manual matrix executed
against both builds:

7 browsers (Safari, Chrome, Brave, Edge, Vivaldi, Firefox, Arc/Dia)
× app already running / not running
× profile specified / not specified

Plus: default-browser registration, rule persistence, tip-jar purchase in the
StoreKit sandbox.

## Implementation order

The riskiest unknown is resolved first, because a negative result changes the
decision rather than merely the code.

1. **Spike** — a throwaway sandboxed binary that opens a URL in a named Chrome
   profile while Chrome is already running. If this fails, the App Store build
   loses profile routing and the dual-channel decision must be revisited.
2. `project.yml` configurations, both entitlements files, `Capabilities`
3. `BrowserLauncher` rewrite to async `NSWorkspace`
4. UI changes — default-browser card, running-apps union
5. `TipJar.swift` + `Products.storekit`
6. `scripts/build-appstore.sh`
7. `.github/workflows/release.yml`
8. Documentation sweep

## Open considerations

**Deployment target stays at macOS 26.0 — decided, not inherited.**

This was investigated empirically by compiling the app at every candidate target
(Xcode 26.6, SDK macOS 26.5):

| Target | Result |
|---|---|
| 15.0 / 14.0 / 13.3 | Builds with zero source changes |
| 13.0 | One blocker: `scrollBounceBehavior(_:axes:)` requires 13.3 |
| 12.0 | Hard floor — `MenuBarExtra`, `Window`, `openWindow`, `defaultSize`, and `windowResizability` are all macOS 13 |

So **nothing in the current codebase requires macOS 26**. The README previously
claimed the UI "uses Liquid Glass APIs that aren't backported"; that was
incorrect. `glassCard()` (`SettingsView.swift:498`) is a project-local modifier
built on `.ultraThinMaterial` and `.regularMaterial`, available since macOS 12.
No Apple glass API is used anywhere.

The target nevertheless **remains 26.0** by explicit decision: the interface is
about to be redesigned around genuine Liquid Glass (`glassEffect`,
`GlassEffectContainer`, `.buttonStyle(.glass)`), which is macOS 26-only with no
back-deployment path. Supporting 13.0 would mean designing and maintaining two
visual treatments behind `#available`, and the older path would inevitably
degrade.

**Consequence to accept knowingly:** the App Store listing reaches only Tahoe and
later. For a free utility this is a significant reduction in addressable
audience, and it is the single largest constraint on adoption in this plan. The
README now states the reason honestly rather than claiming a technical
requirement that does not exist.

**Implication for the redesign:** because the target stays at 26.0, no
availability gating is needed anywhere, and `GlassCardModifier` can be replaced
outright rather than branched. The Liquid Glass redesign is separate work and is
not part of this spec, but it should land **before** the first App Store
submission so the store screenshots show the final design.

**`OpenElsewhere/.git`** is a stale duplicate clone of this same repository. The
authoritative sources are tracked by the outer repo. Deleting the inner `.git`
and its duplicated `LICENSE`, `README.md`, `.gitignore`, and `.xcodeproj` is
recommended housekeeping, out of scope here.
