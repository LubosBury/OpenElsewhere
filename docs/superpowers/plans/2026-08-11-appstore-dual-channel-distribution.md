# Dual-Channel Distribution Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship OpenElsewhere on the Mac App Store as a sandboxed build, while keeping a Developer ID–signed, notarized DMG distributed through a Homebrew cask.

**Architecture:** One XcodeGen target with two build configurations. `Release` signs with Developer ID and stays unsandboxed; `ReleaseAppStore` signs with Apple Distribution, enables the App Sandbox, and defines `APP_STORE`. A single `Capabilities` enum is the only place conditional compilation appears — every feature site reads a boolean. `BrowserLauncher` drops `Process` entirely in favour of async `NSWorkspace` APIs that are legal in both worlds.

**Tech Stack:** Swift 5.9, SwiftUI, AppKit, StoreKit 2, XcodeGen, xcodebuild, notarytool, GitHub Actions, Homebrew Cask.

## Global Constraints

- **Deployment target stays `macOS 26.0`** in both `project.yml:5` and `project.yml:38`. Do not lower it. A Liquid Glass redesign is landing separately and depends on it.
- **Bundle identifier is `com.openelsewhere.app`** for both configurations. Never diverge it.
- **Development Team ID is `78QQBJB52G`.**
- **Swift version `5.9`**, as already set in `project.yml:39`.
- **`#if APP_STORE` may appear in exactly one file:** `OpenElsewhere/Sources/Capabilities.swift`. Any other occurrence is a defect.
- **No new third-party dependencies.** The project has none and adds none.
- **No test target exists and none is being added.** AppKit/LaunchServices/StoreKit integration behaviour is not meaningfully unit-testable here. Verification is by compile checks, signed-artifact inspection, and an explicit manual matrix. Where a step says "manual verification", it is a required gate, not a suggestion.
- **Xcode is not on the `xcode-select` path.** Every `xcodebuild` invocation must be prefixed with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`, or the build fails with "requires Xcode, but active developer directory is a command line tools instance".
- **IAP product IDs**, exactly: `com.openelsewhere.app.tip.small`, `com.openelsewhere.app.tip.medium`, `com.openelsewhere.app.tip.large`.
- **Liquid Glass redesign is out of scope.** Do not restyle anything. Where this plan adds UI, match the surrounding idiom in `SettingsView.swift` (`glassCard()`, `accent`, `.font(.caption)`) so the redesign has one consistent thing to replace.

## Prerequisite

Task 8 (`create-dmg`) and Task 1 require tooling. Install before starting:

```bash
brew install create-dmg
```

The manual Apple-side setup (certificates, App Store Connect record, IAP products) is tracked separately in `docs/APPSTORE-SETUP.md` and is the user's responsibility. Tasks 6 and 7 produce artifacts that depend on step 1a and step 2 of that runbook being complete.

## File Structure

| Path | Status | Responsibility |
|---|---|---|
| `spike/project.yml` | Create (Task 1) | Throwaway XcodeGen project for the sandbox spike |
| `spike/Sources/main.swift` | Create (Task 1) | Sandbox spike executable |
| `spike/Resources/Spike.entitlements` | Create (Task 1) | Sandbox + apple-events exception for the spike |
| `OpenElsewhere/Sources/Capabilities.swift` | Create (Task 2) | The single conditional-compilation seam |
| `OpenElsewhere/Resources/OpenElsewhere-AppStore.entitlements` | Create (Task 2) | Sandbox, network, apple-events exception |
| `project.yml` | Modify (Task 2) | Two configurations, per-config signing |
| `OpenElsewhere/Sources/BrowserLauncher.swift` | Modify (Task 3) | `Process` → async `NSWorkspace` |
| `OpenElsewhere/Sources/AppDelegate.swift` | Modify (Task 3) | Wrap the now-async launcher in a `Task` |
| `OpenElsewhere/Sources/BrowserDiscovery.swift` | Modify (Task 4) | Gate `~/Applications`, union running apps |
| `OpenElsewhere/Sources/SettingsView.swift` | Modify (Tasks 4, 5) | Default-browser card, tip jar UI |
| `OpenElsewhere/Sources/TipJar.swift` | Create (Task 5) | StoreKit 2 consumable purchases |
| `OpenElsewhere/Resources/Products.storekit` | Create (Task 5) | Local StoreKit testing configuration |
| `scripts/build-appstore.sh` | Create (Task 6) | Archive for App Store, open Organizer |
| `scripts/build-dmg.sh` | Modify (Task 7) | Sign with Developer ID, optional notarization |
| `.github/workflows/release.yml` | Create (Task 7) | Tag-triggered signed + notarized DMG release |
| `README.md`, `RELEASING.md`, `Casks/openelsewhere.rb`, `PRIVACY.md` | Modify/Create (Task 8) | Documentation sweep |

---

### Task 1: Spike — prove sandboxed browser routing works

**This task can invalidate the whole plan.** If Step 6 fails, stop and report before touching the real project: the App Store build would lose profile routing, and the dual-channel decision needs revisiting with the user.

**Files:**
- Create: `spike/project.yml`
- Create: `spike/Sources/main.swift`
- Create: `spike/Resources/Spike.entitlements`
- Create: `spike/.gitignore`

**Interfaces:**
- Consumes: nothing.
- Produces: a go/no-go answer recorded in the commit message. No code that later tasks import.

- [ ] **Step 1: Create the working branch**

```bash
cd /Users/lubosbury/DEV/OpenElswhere
git checkout -b appstore-distribution
```

- [ ] **Step 2: Create the spike entitlements**

Create `spike/Resources/Spike.entitlements`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <true/>
    <key>com.apple.security.automation.apple-events</key>
    <true/>
    <key>com.apple.security.temporary-exception.apple-events</key>
    <array>
        <string>company.thebrowser.Browser</string>
        <string>company.thebrowser.dia</string>
    </array>
</dict>
</plist>
```

- [ ] **Step 3: Create the spike project definition**

Create `spike/project.yml`:

```yaml
name: ProfileSpike
options:
  bundleIdPrefix: com.openelsewhere
  deploymentTarget:
    macOS: "26.0"

targets:
  ProfileSpike:
    type: application
    platform: macOS
    sources:
      - Sources
    info:
      path: Resources/Info.plist
      properties:
        LSUIElement: true
        NSAppleEventsUsageDescription: "Spike test for Apple Events under sandbox."
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.openelsewhere.profilespike
        MACOSX_DEPLOYMENT_TARGET: "26.0"
        SWIFT_VERSION: "5.9"
        CODE_SIGN_IDENTITY: "Apple Development"
        CODE_SIGN_STYLE: Automatic
        DEVELOPMENT_TEAM: 78QQBJB52G
        CODE_SIGN_ENTITLEMENTS: Resources/Spike.entitlements
```

Create `spike/.gitignore`:

```
build/
ProfileSpike.xcodeproj/
Resources/Info.plist
```

- [ ] **Step 4: Write the spike**

Create `spike/Sources/main.swift`:

```swift
import AppKit

// Sandboxed spike. Answers two questions the App Store migration depends on:
//
//   1. Can a sandboxed process route a URL into a *specific* Chrome profile
//      while Chrome is already running? (NSWorkspace.openApplication with
//      createsNewApplicationInstance, relying on Chrome's singleton IPC.)
//   2. Can a sandboxed process drive Arc/Dia via AppleScript given only a
//      temporary-exception entitlement?
//
// Run the binary directly from Terminal so stdout is visible. The kernel
// still applies the sandbox, because it keys off the code signature.

func log(_ message: String) {
    FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
}

func testChromeProfile(profileDirectory: String, urlString: String) async -> Bool {
    let bundleID = "com.google.Chrome"
    guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
        log("SKIP chrome: not installed")
        return false
    }

    let config = NSWorkspace.OpenConfiguration()
    config.createsNewApplicationInstance = true
    config.activates = true
    config.arguments = ["--profile-directory=\(profileDirectory)", urlString]

    do {
        let app = try await NSWorkspace.shared.openApplication(at: appURL, configuration: config)
        log("PASS chrome: openApplication returned pid \(app.processIdentifier)")
        log("      >>> NOW LOOK AT CHROME. Did \(urlString) open in profile '\(profileDirectory)'?")
        return true
    } catch {
        log("FAIL chrome: \(error)")
        return false
    }
}

func testArcAppleScript(urlString: String) -> Bool {
    let bundleID = "company.thebrowser.Browser"
    let running = NSRunningApplication
        .runningApplications(withBundleIdentifier: bundleID)
        .contains { !$0.isTerminated }
    guard running else {
        log("SKIP arc: not running (launch Arc and re-run to test this path)")
        return false
    }

    let source = """
    tell application "Arc"
        activate
        if (count of windows) is 0 then
            make new window
        end if
        tell front window
            make new tab with properties {URL:"\(urlString)"}
        end tell
    end tell
    """

    guard let script = NSAppleScript(source: source) else {
        log("FAIL arc: could not compile script")
        return false
    }

    var errorInfo: NSDictionary?
    _ = script.executeAndReturnError(&errorInfo)

    if let info = errorInfo {
        let code = (info[NSAppleScript.errorNumber] as? Int) ?? 0
        log("FAIL arc (\(code)): \(info)")
        // -1743 means the user denied automation permission, which is a TCC
        // prompt result, not an entitlement failure. Re-run after approving.
        return false
    }
    log("PASS arc: tab created in front window")
    return true
}

let profile = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Default"
let url = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "https://example.com"

log("=== sandbox spike: profile='\(profile)' url='\(url)' ===")

let semaphore = DispatchSemaphore(value: 0)
Task {
    _ = await testChromeProfile(profileDirectory: profile, urlString: url)
    _ = testArcAppleScript(urlString: url)
    semaphore.signal()
}
semaphore.wait()
log("=== spike complete ===")
```

- [ ] **Step 5: Build the spike**

```bash
cd /Users/lubosbury/DEV/OpenElswhere/spike
xcodegen generate
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project ProfileSpike.xcodeproj -scheme ProfileSpike \
  -configuration Debug -derivedDataPath build build 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`

Confirm the sandbox entitlement actually made it into the signature:

```bash
codesign -d --entitlements - --xml build/Build/Products/Debug/ProfileSpike.app 2>/dev/null \
  | plutil -convert xml1 -o - - | grep -A1 app-sandbox
```

Expected: `<key>com.apple.security.app-sandbox</key>` followed by `<true/>`.

- [ ] **Step 6: Run the spike — THE DECISION GATE**

Preparation, done by hand:
1. Launch Chrome.
2. Confirm it has at least two profiles (Chrome menu → Profiles). Note the *directory* name of the second one — it is `Profile 1`, not the display name. Verify with:
   `ls ~/Library/Application\ Support/Google/Chrome/ | grep -i profile`
3. Leave Chrome running, with a window open on the **Default** profile.
4. Optionally launch Arc to exercise the second check.

Then:

```bash
cd /Users/lubosbury/DEV/OpenElswhere/spike
./build/Build/Products/Debug/ProfileSpike.app/Contents/MacOS/ProfileSpike \
  "Profile 1" "https://example.com"
```

Expected on success:
```
=== sandbox spike: profile='Profile 1' url='https://example.com' ===
PASS chrome: openApplication returned pid <n>
      >>> NOW LOOK AT CHROME. Did https://example.com open in profile 'Profile 1'?
```

**The printed `PASS` is not sufficient.** `openApplication` returning successfully only proves a process launched. Visually confirm the URL opened in a **`Profile 1` window**, not in the Default profile window.

Record the outcome:

- **URL opened in `Profile 1`** → profile routing survives sandboxing. Proceed to Task 2, and in Task 3 set `canSpawnProcesses` usage aside — both builds share the `NSWorkspace` path.
- **URL opened, but in the Default profile** → `configuration.arguments` is ignored for the already-running case. The App Store build loses profile routing. **STOP and report to the user** before continuing.
- **`FAIL chrome:`** → **STOP and report.**

For Arc: `PASS arc` confirms the temporary-exception entitlement works under sandbox. `FAIL arc (-1743)` only means automation permission was not granted — approve the macOS prompt and re-run before concluding anything.

- [ ] **Step 7: Commit the spike and its result**

```bash
cd /Users/lubosbury/DEV/OpenElswhere
git add spike/
git commit -m "Add sandbox spike for Chrome profile routing and Arc AppleScript

Result: <PASTE THE ACTUAL OUTCOME HERE — which profile the URL opened in,
and whether the Arc AppleScript path succeeded>"
```

Replace the placeholder with the observed result. This commit message is the record of the decision gate.

---

### Task 2: Build configurations, entitlements, and the Capabilities seam

**Files:**
- Create: `OpenElsewhere/Sources/Capabilities.swift`
- Create: `OpenElsewhere/Resources/OpenElsewhere-AppStore.entitlements`
- Modify: `project.yml`

**Interfaces:**
- Consumes: nothing.
- Produces: `Capabilities.canSetDefaultBrowser`, `Capabilities.canEnumerateUserApplications`, `Capabilities.showsExternalDonationLink` — all `static let Bool`. Tasks 4 and 5 read these. Also produces the `ReleaseAppStore` build configuration name, used by Tasks 6 and 7.

- [ ] **Step 1: Create the App Store entitlements**

Create `OpenElsewhere/Resources/OpenElsewhere-AppStore.entitlements`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <true/>

    <!-- StoreKit needs outbound network access. Omitting this fails at
         runtime with an opaque product-load error, not at build time. -->
    <key>com.apple.security.network.client</key>
    <true/>

    <key>com.apple.security.automation.apple-events</key>
    <true/>

    <!-- Scoped to exactly two bundle IDs. Arc and Dia refuse a second process
         instance and open LaunchServices-delivered URLs in a detached popup
         rather than a tab; a single "make new tab" event is the only way to
         get the expected behaviour. Justified in App Review notes. -->
    <key>com.apple.security.temporary-exception.apple-events</key>
    <array>
        <string>company.thebrowser.Browser</string>
        <string>company.thebrowser.dia</string>
    </array>
</dict>
</plist>
```

- [ ] **Step 2: Create the Capabilities seam**

Create `OpenElsewhere/Sources/Capabilities.swift`:

```swift
import Foundation

/// Compile-time capability switches for the two distribution channels.
///
/// The App Store build runs inside the App Sandbox, which forbids three things
/// the Developer ID build can do. This enum is the **only** place `#if APP_STORE`
/// is allowed to appear — every feature site reads a boolean instead, so the
/// conditional compilation never spreads into behaviour code.
enum Capabilities {
    #if APP_STORE

    /// Apple has not extended runtime default-handler APIs to sandboxed apps,
    /// so `NSWorkspace.setDefaultApplication` cannot be used. The UI guides the
    /// user to System Settings instead.
    static let canSetDefaultBrowser = false

    /// Under the sandbox, `homeDirectoryForCurrentUser` resolves to the app's
    /// container, so `~/Applications` is not reachable.
    static let canEnumerateUserApplications = false

    /// App Review restricts donation links for individual developers; the App
    /// Store build offers a StoreKit tip jar instead.
    static let showsExternalDonationLink = false

    #else

    static let canSetDefaultBrowser = true
    static let canEnumerateUserApplications = true
    static let showsExternalDonationLink = true

    #endif
}
```

> **Why only three flags.** The spec also anticipated `isSandboxed` and
> `canSpawnProcesses`. Neither has a reader: Task 3 removes `Process` from the
> shared path entirely rather than keeping a second launcher, and nothing needs
> to ask whether it is sandboxed in the abstract. Adding unread constants would
> be dead code. If the Task 1 spike fails and the `Process` contingency has to
> be resurrected, `canSpawnProcesses` gets added *then*, together with the code
> that reads it.

- [ ] **Step 3: Add the configurations to project.yml**

In `project.yml`, insert a top-level `configs:` block immediately after the `options:` block (after line 6, `xcodeVersion: "16.0"`), before `targets:`:

```yaml
configs:
  Debug: debug
  Release: release
  ReleaseAppStore: release
```

- [ ] **Step 4: Add the export-compliance key to Info.plist properties**

In `project.yml`, inside `targets.OpenElsewhere.info.properties`, add one key alongside the existing `LSUIElement`:

```yaml
        ITSAppUsesNonExemptEncryption: false
```

The app uses no encryption beyond Apple's own frameworks. Declaring this in the bundle avoids being asked the export-compliance question on every single App Store upload.

- [ ] **Step 5: Replace the target settings block with per-configuration signing**

In `project.yml`, replace the entire existing `settings:` block (lines 34–44, from `    settings:` through the `CODE_SIGN_ENTITLEMENTS` line) with:

```yaml
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.openelsewhere.app
        PRODUCT_NAME: OpenElsewhere
        MACOSX_DEPLOYMENT_TARGET: "26.0"
        SWIFT_VERSION: "5.9"
        INFOPLIST_FILE: OpenElsewhere/Resources/Info.plist
        DEVELOPMENT_TEAM: 78QQBJB52G
        ENABLE_HARDENED_RUNTIME: YES
        CODE_SIGN_ENTITLEMENTS: OpenElsewhere/Resources/OpenElsewhere.entitlements
      configs:
        Debug:
          CODE_SIGN_IDENTITY: "Apple Development"
          CODE_SIGN_STYLE: Automatic
        Release:
          # Developer ID channel: notarized DMG via Homebrew. Not sandboxed.
          CODE_SIGN_IDENTITY: "Developer ID Application"
          CODE_SIGN_STYLE: Manual
        ReleaseAppStore:
          # Mac App Store channel: sandboxed, Apple Distribution signed.
          CODE_SIGN_IDENTITY: "Apple Distribution"
          CODE_SIGN_STYLE: Manual
          CODE_SIGN_ENTITLEMENTS: OpenElsewhere/Resources/OpenElsewhere-AppStore.entitlements
          SWIFT_ACTIVE_COMPILATION_CONDITIONS: APP_STORE
```

Note `ENABLE_HARDENED_RUNTIME: YES` stays in `base` — it is required for notarization and harmless for the App Store build.

- [ ] **Step 6: Regenerate and verify both configurations compile**

```bash
cd /Users/lubosbury/DEV/OpenElswhere
xcodegen generate
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

xcodebuild -project OpenElsewhere.xcodeproj -scheme OpenElsewhere \
  -configuration Release -derivedDataPath /tmp/oe-rel \
  CODE_SIGNING_ALLOWED=NO clean build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)"

xcodebuild -project OpenElsewhere.xcodeproj -scheme OpenElsewhere \
  -configuration ReleaseAppStore -derivedDataPath /tmp/oe-mas \
  CODE_SIGNING_ALLOWED=NO clean build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)"
```

Expected: `** BUILD SUCCEEDED **` from both.

- [ ] **Step 7: Verify the APP_STORE flag actually reaches the compiler**

Temporarily append this line to the end of `Capabilities.swift`:

```swift
#if APP_STORE
#warning("APP_STORE flag is active")
#endif
```

Rebuild `ReleaseAppStore` and confirm the warning appears:

```bash
xcodebuild -project OpenElsewhere.xcodeproj -scheme OpenElsewhere \
  -configuration ReleaseAppStore -derivedDataPath /tmp/oe-mas \
  CODE_SIGNING_ALLOWED=NO build 2>&1 | grep "APP_STORE flag is active"
```

Expected: one line containing `APP_STORE flag is active`.

Then rebuild `Release` and confirm the warning is **absent**:

```bash
xcodebuild -project OpenElsewhere.xcodeproj -scheme OpenElsewhere \
  -configuration Release -derivedDataPath /tmp/oe-rel \
  CODE_SIGNING_ALLOWED=NO build 2>&1 | grep -c "APP_STORE flag is active"
```

Expected: `0`

Now **delete the temporary `#warning` block** from `Capabilities.swift`.

- [ ] **Step 8: Commit**

```bash
git add project.yml OpenElsewhere.xcodeproj \
  OpenElsewhere/Sources/Capabilities.swift \
  OpenElsewhere/Resources/OpenElsewhere-AppStore.entitlements
git commit -m "Add ReleaseAppStore configuration, sandbox entitlements, and Capabilities seam"
```

---

### Task 3: Rewrite BrowserLauncher on async NSWorkspace

**Files:**
- Modify: `OpenElsewhere/Sources/BrowserLauncher.swift` (whole-file rewrite)
- Modify: `OpenElsewhere/Sources/AppDelegate.swift:29-45`

**Interfaces:**
- Consumes: `Capabilities` (Task 2) — not read directly here, but the file must compile under both configurations. `BrowserCapabilities.forBundleID(_:)` and `BrowserFamily` from `BrowserProfile.swift`.
- Produces: `@MainActor BrowserLauncher.open(_ url: URL, inBrowser bundleID: String, profileDirectory: String?) async` — note this is now **async** and **@MainActor**. `BrowserLauncher.automationDeniedDefaultsKey: String` is unchanged and still read by `SettingsView.swift:12`.

- [ ] **Step 1: Rewrite BrowserLauncher.swift**

Replace the entire contents of `OpenElsewhere/Sources/BrowserLauncher.swift` with:

```swift
import AppKit
import Foundation

/// Opens URLs in specific browsers, optionally targeting a named profile.
///
/// macOS has no single correct way to hand a URL to a running browser with a
/// specific profile. Different browsers need different strategies:
///
/// - **Chrome / Brave / Edge / Vivaldi / Opera**: implement a binary-level
///   singleton protocol. Starting a second instance with `--profile-directory=X`
///   is detected by the existing instance (via a file lock in the user-data-dir),
///   the command line is forwarded over IPC, and the existing browser opens the
///   URL in the target profile. We reach that behaviour through
///   `NSWorkspace.openApplication` with `createsNewApplicationInstance`, which
///   is legal inside the App Sandbox — unlike spawning the binary via `Process`.
///
/// - **Arc / Dia** (The Browser Company): strictly single-instance. When they
///   receive a URL through LaunchServices they open it in a detached popup
///   ("Little Arc") rather than a tab. A single AppleScript event asking for a
///   new tab in the front window is the only way to get the expected behaviour.
///   Under the App Store build this relies on the
///   `com.apple.security.temporary-exception.apple-events` entitlement.
///
/// - **Firefox**: handles multi-launch gracefully via its own remote protocol.
///
/// - **Safari / unknown**: defer to LaunchServices. No profile CLI.
///
/// `@MainActor` because `NSAppleScript` must run on the main thread, and every
/// caller (the `AppDelegate` Apple Event handler) is already main-isolated.
@MainActor
enum BrowserLauncher {

    /// UserDefaults key set to `true` when macOS blocks an automation event
    /// with `errAEEventNotPermitted` (-1743). `SettingsView` observes this
    /// key to show a one-click remediation banner.
    ///
    /// `nonisolated` because `SettingsView` reads it from a stored-property
    /// initializer (`@AppStorage(BrowserLauncher.automationDeniedDefaultsKey)`),
    /// which is not main-actor isolated. Without this, making the enum
    /// `@MainActor` breaks that call site.
    nonisolated static let automationDeniedDefaultsKey = "automationPermissionDenied"

    /// AppleScript error code returned when the user has denied (or not yet
    /// granted) automation permission in Privacy settings.
    private static let errAEEventNotPermitted = -1743

    /// Scripting targets for the single-instance browsers we route through
    /// AppleScript. Hardcoding these defends against a malicious app that
    /// registers a conflicting bundle ID with a hostile `CFBundleName`: the
    /// name is never read from disk, only sourced from this trusted map.
    /// This list must stay in sync with the `temporary-exception.apple-events`
    /// array in `OpenElsewhere-AppStore.entitlements`.
    private static let knownScriptingNames: [String: String] = [
        "company.thebrowser.Browser": "Arc",
        "company.thebrowser.dia": "Dia",
        "com.thebrowser.dia": "Dia"
    ]

    static func open(_ url: URL,
                     inBrowser bundleID: String,
                     profileDirectory: String? = nil) async {
        guard let browserAppURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            NSWorkspace.shared.open(url)
            return
        }

        let caps = BrowserCapabilities.forBundleID(bundleID)

        switch caps.family {
        case .chromium where isStrictSingleInstance(bundleID: bundleID, appURL: browserAppURL):
            // Arc, Dia — a second instance is refused outright, so AppleScript
            // is the only route to tab behaviour. Fall back to a plain open,
            // which yields the popup but at least delivers the URL.
            if launchViaAppleScript(url: url, bundleID: bundleID) { return }
            await openURL(url, inAppAt: browserAppURL)

        case .chromium:
            let args = chromiumProfileArgs(profileDirectory) + [url.absoluteString]
            if await launchWithArguments(appURL: browserAppURL, arguments: args) { return }
            await openURL(url, inAppAt: browserAppURL)

        case .firefox:
            let args = firefoxProfileArgs(profileDirectory) + ["--new-tab", url.absoluteString]
            if await launchWithArguments(appURL: browserAppURL, arguments: args) { return }
            await openURL(url, inAppAt: browserAppURL)

        case .safari, .unknown:
            await openURL(url, inAppAt: browserAppURL)
        }
    }

    // MARK: - Detection

    /// Browsers we know enforce a single-instance policy at the binary level.
    /// Detected either via `LSMultipleInstancesProhibited` in Info.plist or
    /// via an explicit allow-list for apps that do the check in their own
    /// startup code (like Arc).
    private static func isStrictSingleInstance(bundleID: String, appURL: URL) -> Bool {
        if knownScriptingNames[bundleID] != nil { return true }

        if let bundle = Bundle(url: appURL),
           let prohibit = bundle.object(forInfoDictionaryKey: "LSMultipleInstancesProhibited") as? Bool,
           prohibit {
            return true
        }
        return false
    }

    // MARK: - Profile arg helpers

    private static func chromiumProfileArgs(_ profile: String?) -> [String] {
        guard let profile, !profile.isEmpty else { return [] }
        return ["--profile-directory=\(profile)"]
    }

    private static func firefoxProfileArgs(_ profile: String?) -> [String] {
        guard let profile, !profile.isEmpty else { return [] }
        return ["-P", profile]
    }

    // MARK: - AppleScript helpers

    /// Strip ASCII control characters (C0 + DEL) from a string before
    /// embedding it in an AppleScript literal. Foundation will percent-encode
    /// control chars in a normal `URL`, but we filter defensively in case a
    /// malformed URL reaches us or a future code path passes untrusted text.
    /// After filtering, we escape the two AppleScript string-literal
    /// metacharacters: backslash and double-quote.
    private static func sanitizeForAppleScriptLiteral(_ value: String) -> String {
        let filtered = String(value.unicodeScalars.filter { scalar in
            let v = scalar.value
            return v >= 0x20 && v != 0x7F
        })
        return filtered
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    // MARK: - Launch strategies

    /// Start a (possibly second) instance of the app with command-line
    /// arguments. Chromium and Firefox both treat this as "forward these
    /// arguments to the running instance over IPC", which is how profile
    /// targeting works. Returns `false` if the launch failed.
    private static func launchWithArguments(appURL: URL, arguments: [String]) async -> Bool {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        configuration.activates = true
        configuration.arguments = arguments

        do {
            _ = try await NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
            return true
        } catch {
            print("OpenElsewhere: openApplication(\(appURL.lastPathComponent)) failed: \(error.localizedDescription)")
            return false
        }
    }

    /// Hand the URL to LaunchServices for the given app. This is the universal
    /// fallback: no profile targeting, but it always delivers the URL.
    private static func openURL(_ url: URL, inAppAt appURL: URL) async {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true

        do {
            _ = try await NSWorkspace.shared.open([url],
                                                  withApplicationAt: appURL,
                                                  configuration: configuration)
        } catch {
            print("OpenElsewhere: open(\(url.absoluteString)) in \(appURL.lastPathComponent) failed: \(error.localizedDescription)")
            NSWorkspace.shared.open(url)
        }
    }

    /// For strictly single-instance Chromium browsers (Arc, Dia), send the
    /// URL directly to the front window via AppleScript. Returns `true` on
    /// success; the caller falls back to a plain open on `false`.
    private static func launchViaAppleScript(url: URL, bundleID: String) -> Bool {
        // Only run if the target app is actually running — otherwise the
        // AppleEvent would force-launch it with no window, and `front window`
        // would fail. Let the caller's fallback cold-start it instead.
        let isRunning = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleID)
            .contains { !$0.isTerminated }
        guard isRunning else { return false }

        // `scriptingName` is sourced from our trusted allow-list, never from
        // an on-disk bundle's `CFBundleName`. A malicious app that registers
        // a conflicting bundle ID cannot poison the AppleScript target.
        guard let scriptingName = knownScriptingNames[bundleID] else { return false }

        let escapedURL = sanitizeForAppleScriptLiteral(url.absoluteString)

        let source = """
        tell application "\(scriptingName)"
            activate
            if (count of windows) is 0 then
                make new window
            end if
            tell front window
                make new tab with properties {URL:"\(escapedURL)"}
            end tell
        end tell
        """

        guard let script = NSAppleScript(source: source) else { return false }

        var errorInfo: NSDictionary?
        _ = script.executeAndReturnError(&errorInfo)

        if let info = errorInfo {
            let code = (info[NSAppleScript.errorNumber] as? Int) ?? 0
            print("OpenElsewhere: AppleScript for \(scriptingName) failed (\(code)): \(info)")

            // If the user has denied automation permission, set a flag that
            // SettingsView surfaces as a remediation banner. Users otherwise
            // silently get the "Little Arc" popup with no explanation.
            if code == errAEEventNotPermitted {
                UserDefaults.standard.set(true, forKey: automationDeniedDefaultsKey)
            }
            return false
        }

        // Clear any stale permission-denied flag on a successful run, so the
        // banner disappears after the user grants permission.
        if UserDefaults.standard.bool(forKey: automationDeniedDefaultsKey) {
            UserDefaults.standard.set(false, forKey: automationDeniedDefaultsKey)
        }
        return true
    }
}
```

- [ ] **Step 2: Update AppDelegate for the async launcher**

In `OpenElsewhere/Sources/AppDelegate.swift`, replace the `dispatch(event:)` method (lines 29–45) with:

```swift
    private func dispatch(event: NSAppleEventDescriptor) {
        guard let urlString = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
              let url = URL(string: urlString) else { return }

        let senderBundleID = resolveSenderBundleID(from: event)
        let engine = RoutingEngine.shared

        // `BrowserLauncher.open` is async because `NSWorkspace.openApplication`
        // is. The Apple Event handler cannot await, so the work is handed to a
        // main-actor Task; the event returns immediately, which is correct —
        // the sender does not wait on us.
        guard engine.isEnabled else {
            let fallbackBrowser = engine.defaultBrowserBundleID
            Task { await BrowserLauncher.open(url, inBrowser: fallbackBrowser) }
            return
        }

        let destination = engine.destination(forSourceApp: senderBundleID)
        Task {
            await BrowserLauncher.open(url,
                                       inBrowser: destination.browserBundleID,
                                       profileDirectory: destination.profileDirectoryName)
        }
    }
```

- [ ] **Step 3: Verify both configurations compile**

```bash
cd /Users/lubosbury/DEV/OpenElswhere
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
for CFG in Release ReleaseAppStore; do
  echo "--- $CFG ---"
  xcodebuild -project OpenElsewhere.xcodeproj -scheme OpenElsewhere \
    -configuration $CFG -derivedDataPath /tmp/oe-$CFG \
    CODE_SIGNING_ALLOWED=NO clean build 2>&1 \
    | grep -E "error:|warning: .*concurrency|BUILD (SUCCEEDED|FAILED)"
done
```

Expected: `** BUILD SUCCEEDED **` for both, no `error:` lines.

- [ ] **Step 4: Confirm Process is gone**

```bash
grep -n "Process\|/usr/bin/open" OpenElsewhere/Sources/BrowserLauncher.swift
```

Expected: no output. Any match means the rewrite is incomplete and the App Store build will fail at runtime.

- [ ] **Step 5: Manual verification — the routing matrix**

Build and run the unsandboxed `Release` app, set it as default browser, then work through this matrix. For each cell, click a link in a source app and confirm the destination.

| Browser | Not running, no profile | Running, no profile | Running, with profile |
|---|---|---|---|
| Safari | opens | opens in existing window | n/a |
| Chrome | opens | new tab | new tab **in the named profile** |
| Brave | opens | new tab | new tab in named profile |
| Edge | opens | new tab | new tab in named profile |
| Vivaldi | opens | new tab | new tab in named profile |
| Firefox | opens | new tab | new tab in named profile |
| Arc / Dia | opens (popup acceptable) | **new tab in front window, not a popup** | best-effort, popup acceptable |

Skip rows for browsers not installed. The Arc "running" cell is the one that regresses most visibly if the AppleScript path breaks — check it deliberately.

Then repeat the **Chrome running + profile** and **Arc running** cells against the `ReleaseAppStore` build:

```bash
xcodebuild -project OpenElsewhere.xcodeproj -scheme OpenElsewhere \
  -configuration ReleaseAppStore -derivedDataPath /tmp/oe-mas build
open /tmp/oe-mas/Build/Products/ReleaseAppStore/OpenElsewhere.app
```

These two cells are the sandbox-sensitive ones. If they behave differently from the `Release` build, report it before continuing.

- [ ] **Step 6: Commit**

```bash
git add OpenElsewhere/Sources/BrowserLauncher.swift OpenElsewhere/Sources/AppDelegate.swift
git commit -m "Replace Process-based launching with async NSWorkspace

Removes the last sandbox-illegal code path. Chromium and Firefox profile
targeting now goes through openApplication with createsNewApplicationInstance,
relying on the same singleton-IPC forwarding as before."
```

---

### Task 4: Sandbox-aware UI — default browser card and app discovery

**Files:**
- Modify: `OpenElsewhere/Sources/BrowserDiscovery.swift:28-61`
- Modify: `OpenElsewhere/Sources/SettingsView.swift` (`statusBanner`, `setAsDefaultBrowser`)

**Interfaces:**
- Consumes: `Capabilities.canSetDefaultBrowser`, `Capabilities.canEnumerateUserApplications` (Task 2).
- Produces: no new public API. `BrowserDiscovery.installedApps()` keeps its `-> [AppInfo]` signature.

- [ ] **Step 1: Make app discovery sandbox-aware**

In `OpenElsewhere/Sources/BrowserDiscovery.swift`, replace the entire `installedApps()` method (lines 28–61) with:

```swift
    func installedApps() -> [AppInfo] {
        var appDirs = [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/System/Applications")
        ]

        // Under the App Sandbox `homeDirectoryForCurrentUser` resolves to the
        // app's container, so scanning it would enumerate nothing useful.
        if Capabilities.canEnumerateUserApplications {
            appDirs.append(
                FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent("Applications")
            )
        }

        var apps: [String: AppInfo] = [:]

        for dir in appDirs {
            guard let enumerator = FileManager.default.enumerator(
                at: dir,
                includingPropertiesForKeys: [.isApplicationKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }

            for case let fileURL as URL in enumerator {
                guard fileURL.pathExtension == "app" else { continue }
                guard let bundle = Bundle(url: fileURL),
                      let bundleID = bundle.bundleIdentifier else { continue }

                let name = FileManager.default.displayName(atPath: fileURL.path)
                // Note: NSWorkspace.icon(forFile:) returns a shared NSImage.
                // Do NOT mutate its `.size` — that would affect every other
                // caller holding the same cached instance.
                let icon = NSWorkspace.shared.icon(forFile: fileURL.path)

                if apps[bundleID] == nil {
                    apps[bundleID] = AppInfo(bundleID: bundleID, name: name, icon: icon)
                }
            }
        }

        // Union with currently-running apps. This recovers most of what the
        // sandbox hides: an app the user is actually using is discoverable
        // wherever it lives, including `~/Applications` and Setapp. It also
        // helps the unsandboxed build find apps in unusual locations.
        for running in NSWorkspace.shared.runningApplications {
            guard running.activationPolicy == .regular,
                  let bundleID = running.bundleIdentifier,
                  let bundleURL = running.bundleURL,
                  apps[bundleID] == nil else { continue }

            apps[bundleID] = AppInfo(
                bundleID: bundleID,
                name: FileManager.default.displayName(atPath: bundleURL.path),
                icon: NSWorkspace.shared.icon(forFile: bundleURL.path)
            )
        }

        return apps.values
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
```

- [ ] **Step 2: Make the default-browser action sandbox-aware**

In `OpenElsewhere/Sources/SettingsView.swift`, replace the `setAsDefaultBrowser()` method with:

```swift
    private func setAsDefaultBrowser() {
        // Apple has not extended runtime default-handler APIs to sandboxed
        // apps, so the App Store build cannot do this itself. Open the
        // relevant System Settings pane instead — opening a URL is legal in
        // the sandbox, so the user still lands one click from the control.
        guard Capabilities.canSetDefaultBrowser else {
            if let settingsURL = URL(string: "x-apple.systempreferences:com.apple.Desktop-Settings.extension") {
                NSWorkspace.shared.open(settingsURL)
            }
            return
        }

        let appURL = Bundle.main.bundleURL

        let group = DispatchGroup()
        for scheme in ["http", "https"] {
            group.enter()
            NSWorkspace.shared.setDefaultApplication(at: appURL,
                                                    toOpenURLsWithScheme: scheme) { error in
                if let error {
                    print("OpenElsewhere: setDefaultApplication(\(scheme)) failed: \(error.localizedDescription)")
                }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            checkIfDefault()
        }
    }
```

- [ ] **Step 3: Adapt the status banner copy and re-check on activation**

In `OpenElsewhere/Sources/SettingsView.swift`, replace the `statusBanner` computed property with:

```swift
    private var statusBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "bolt.horizontal.circle.fill")
                .font(.title2)
                .foregroundStyle(accent)
                .symbolRenderingMode(.hierarchical)

            VStack(alignment: .leading, spacing: 2) {
                Text("OpenElsewhere isn't routing your links yet")
                    .font(.subheadline.weight(.semibold))
                Text(Capabilities.canSetDefaultBrowser
                     ? "Set it as your default link handler so other apps send URLs through it."
                     : "In System Settings, choose OpenElsewhere under \"Default web browser\".")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(Capabilities.canSetDefaultBrowser ? "Make it Default" : "Open System Settings") {
                setAsDefaultBrowser()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(accent.opacity(colorScheme == .dark ? 0.18 : 0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(accent.opacity(0.35), lineWidth: 0.5)
        )
    }
```

- [ ] **Step 4: Re-check default-browser status when the window regains focus**

The sandboxed user leaves the app to change the setting, so the banner must notice on return. In `SettingsView.swift`, find the `body` property and add one modifier immediately after the existing `.onAppear(perform: loadData)` line:

```swift
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didBecomeActiveNotification)) { _ in
            checkIfDefault()
        }
```

- [ ] **Step 5: Verify both configurations compile**

```bash
cd /Users/lubosbury/DEV/OpenElswhere
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
for CFG in Release ReleaseAppStore; do
  echo "--- $CFG ---"
  xcodebuild -project OpenElsewhere.xcodeproj -scheme OpenElsewhere \
    -configuration $CFG -derivedDataPath /tmp/oe-$CFG \
    CODE_SIGNING_ALLOWED=NO clean build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)"
done
```

Expected: `** BUILD SUCCEEDED **` for both.

- [ ] **Step 6: Manual verification**

Run the `ReleaseAppStore` build:

```bash
open /tmp/oe-ReleaseAppStore/Build/Products/ReleaseAppStore/OpenElsewhere.app
```

Confirm all four:
1. The banner button reads **"Open System Settings"**, not "Make it Default".
2. Clicking it opens System Settings at **Desktop & Dock**.
3. After selecting OpenElsewhere as default web browser and switching back to the app, the banner **disappears without a relaunch**.
4. The rule source-app picker lists at least one app that is currently running but not installed in `/Applications` — if you have no such app, launch anything from `~/Applications` first and reopen the picker.

Then run the `Release` build and confirm the button still reads **"Make it Default"** and still works in one click.

- [ ] **Step 7: Commit**

```bash
git add OpenElsewhere/Sources/BrowserDiscovery.swift OpenElsewhere/Sources/SettingsView.swift
git commit -m "Make default-browser flow and app discovery sandbox-aware

App Store build deep-links to System Settings instead of calling the
default-handler API, and re-checks status on window activation. App
discovery unions running applications to recover ~/Applications coverage."
```

---

### Task 5: StoreKit tip jar

**Files:**
- Create: `OpenElsewhere/Sources/TipJar.swift`
- Create: `OpenElsewhere/Resources/Products.storekit`
- Modify: `OpenElsewhere/Sources/SettingsView.swift` (`headerCard`)
- Modify: `project.yml` (add the StoreKit file as a resource)

**Interfaces:**
- Consumes: `Capabilities.showsExternalDonationLink` (Task 2).
- Produces: `@MainActor final class TipJar: ObservableObject` with `static let productIDs: [String]`, `@Published private(set) var products: [Product]`, `@Published private(set) var isPurchasing: Bool`, `@Published var didTip: Bool`, `func loadProducts() async`, `func purchase(_ product: Product) async`.

- [ ] **Step 1: Create the tip jar model**

Create `OpenElsewhere/Sources/TipJar.swift`:

```swift
import Foundation
import StoreKit

/// StoreKit 2 tip jar for the App Store build.
///
/// Products are **consumable**: a tip can be given repeatedly, and consumables
/// carry no "Restore Purchases" obligation. Nothing is unlocked by a purchase,
/// so there is no entitlement state to persist — the transaction is finished
/// immediately and forgotten.
@MainActor
final class TipJar: ObservableObject {

    /// Must match the product IDs created in App Store Connect exactly.
    static let productIDs = [
        "com.openelsewhere.app.tip.small",
        "com.openelsewhere.app.tip.medium",
        "com.openelsewhere.app.tip.large"
    ]

    @Published private(set) var products: [Product] = []
    @Published private(set) var isPurchasing = false

    /// Set after a verified purchase so the UI can show a thank-you.
    @Published var didTip = false

    func loadProducts() async {
        do {
            let loaded = try await Product.products(for: Self.productIDs)
            products = loaded.sorted { $0.price < $1.price }
        } catch {
            // Product loading fails offline, or before the products are
            // approved in App Store Connect. The UI simply shows nothing.
            print("OpenElsewhere: failed to load tip products — \(error.localizedDescription)")
        }
    }

    func purchase(_ product: Product) async {
        guard !isPurchasing else { return }
        isPurchasing = true
        defer { isPurchasing = false }

        do {
            switch try await product.purchase() {
            case .success(let verification):
                switch verification {
                case .verified(let transaction):
                    await transaction.finish()
                    didTip = true
                case .unverified(_, let error):
                    print("OpenElsewhere: unverified tip transaction — \(error.localizedDescription)")
                }
            case .userCancelled, .pending:
                break
            @unknown default:
                break
            }
        } catch {
            print("OpenElsewhere: tip purchase failed — \(error.localizedDescription)")
        }
    }
}
```

- [ ] **Step 2: Create the local StoreKit configuration**

Create it through Xcode so the internal IDs are generated correctly:

**Xcode → File → New → File from Template… → macOS → StoreKit Configuration File**, name it `Products`, save into `OpenElsewhere/Resources/`, and leave "Sync this file with an app in App Store Connect" **unchecked**.

Then in the editor, add three products with the `+` button, type **Consumable**, with exactly these values:

| Product ID | Reference Name | Price | Display Name | Description |
|---|---|---|---|---|
| `com.openelsewhere.app.tip.small` | Small Tip | 1.99 | Small Tip | A small thank you. Unlocks nothing — the app is free. |
| `com.openelsewhere.app.tip.medium` | Medium Tip | 4.99 | Medium Tip | A generous thank you. Unlocks nothing — the app is free. |
| `com.openelsewhere.app.tip.large` | Large Tip | 9.99 | Large Tip | A very generous thank you. Unlocks nothing — the app is free. |

Then enable it for the scheme: **Product → Scheme → Edit Scheme… → Run → Options → StoreKit Configuration → `Products.storekit`**.

- [ ] **Step 3: Register the StoreKit file as a resource**

In `project.yml`, under `targets.OpenElsewhere.resources`, add a second entry so the list reads:

```yaml
    resources:
      - OpenElsewhere/Resources/Assets.xcassets
      - OpenElsewhere/Resources/Products.storekit
```

- [ ] **Step 4: Swap the donation control in the header**

In `OpenElsewhere/Sources/SettingsView.swift`, add a state object alongside the other `@State` properties near the top of `SettingsView`:

```swift
    @StateObject private var tipJar = TipJar()
```

Then replace the `Link(destination: URL(string: "https://buymeacoffee.com/bozka")!) { ... }` block inside `headerCard` (through its trailing `.foregroundStyle(...)` modifier) with:

```swift
            if Capabilities.showsExternalDonationLink {
                Link(destination: URL(string: "https://buymeacoffee.com/bozka")!) {
                    HStack(spacing: 6) {
                        Image(systemName: "cup.and.saucer.fill")
                        Text("Buy Me a Coffee")
                    }
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.yellow.opacity(colorScheme == .dark ? 0.25 : 0.2))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.yellow.opacity(0.4), lineWidth: 0.5)
                    )
                }
                .foregroundStyle(colorScheme == .dark ? .white : .primary)
            } else {
                tipMenu
            }
```

Add the `tipMenu` property next to the other view properties in `SettingsView`:

```swift
    /// App Store build: a StoreKit tip jar in place of the external donation
    /// link, which App Review restricts for individual developers.
    private var tipMenu: some View {
        Menu {
            if tipJar.products.isEmpty {
                Text("Loading…")
            } else {
                ForEach(tipJar.products, id: \.id) { product in
                    Button("\(product.displayName) — \(product.displayPrice)") {
                        Task { await tipJar.purchase(product) }
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: tipJar.didTip ? "heart.fill" : "cup.and.saucer.fill")
                Text(tipJar.didTip ? "Thank you!" : "Leave a Tip")
            }
            .font(.caption.weight(.medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.yellow.opacity(colorScheme == .dark ? 0.25 : 0.2))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.yellow.opacity(0.4), lineWidth: 0.5)
            )
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .disabled(tipJar.isPurchasing)
        .foregroundStyle(colorScheme == .dark ? .white : .primary)
        .task { await tipJar.loadProducts() }
    }
```

- [ ] **Step 5: Verify both configurations compile**

```bash
cd /Users/lubosbury/DEV/OpenElswhere
xcodegen generate
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
for CFG in Release ReleaseAppStore; do
  echo "--- $CFG ---"
  xcodebuild -project OpenElsewhere.xcodeproj -scheme OpenElsewhere \
    -configuration $CFG -derivedDataPath /tmp/oe-$CFG \
    CODE_SIGNING_ALLOWED=NO clean build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)"
done
```

Expected: `** BUILD SUCCEEDED **` for both.

- [ ] **Step 6: Manual verification against the local StoreKit configuration**

Run the app from Xcode with the `ReleaseAppStore` configuration and the StoreKit configuration attached (Step 2), then confirm:

1. The header shows **"Leave a Tip"**, not "Buy Me a Coffee".
2. Opening the menu lists three tiers with prices, cheapest first.
3. Choosing one shows the StoreKit test purchase sheet; confirming it flips the label to **"Thank you!"** with a filled heart.
4. Cancelling the sheet leaves the label unchanged and the menu still usable.

Then run the `Release` build and confirm the header still shows **"Buy Me a Coffee"** linking out to the external page.

> Note: `Product.products(for:)` returns an empty array when neither a local StoreKit configuration nor approved App Store Connect products are available. An empty menu showing "Loading…" forever in a plain `xcodebuild` run is expected, not a bug.

- [ ] **Step 7: Commit**

```bash
git add OpenElsewhere/Sources/TipJar.swift OpenElsewhere/Resources/Products.storekit \
  OpenElsewhere/Sources/SettingsView.swift project.yml OpenElsewhere.xcodeproj
git commit -m "Add StoreKit 2 consumable tip jar for the App Store build

Replaces the external Buy Me a Coffee link, which App Review restricts for
individual developers. The Developer ID build keeps the link."
```

---

### Task 6: App Store archive script

**Files:**
- Create: `scripts/build-appstore.sh`

**Interfaces:**
- Consumes: the `ReleaseAppStore` configuration (Task 2).
- Produces: `build/OpenElsewhere-AppStore.xcarchive`, opened in Xcode Organizer.

- [ ] **Step 1: Write the script**

Create `scripts/build-appstore.sh`:

```bash
#!/usr/bin/env bash
# Archive OpenElsewhere for Mac App Store submission.
#
# Usage: scripts/build-appstore.sh
#
# Produces build/OpenElsewhere-AppStore.xcarchive and opens it in Xcode
# Organizer. Upload from there via Distribute App -> App Store Connect, which
# handles installer-certificate creation and gives you the validation UI.

set -euo pipefail

SCHEME="OpenElsewhere"
CONFIG="ReleaseAppStore"
BUILD_DIR="build"
ARCHIVE_PATH="${BUILD_DIR}/OpenElsewhere-AppStore.xcarchive"

# Xcode is not necessarily on the xcode-select path on this machine.
if [[ -z "${DEVELOPER_DIR:-}" ]] && [[ -d /Applications/Xcode.app ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

command -v xcodegen >/dev/null || {
  echo "Missing dependency: xcodegen" >&2
  echo "  brew install xcodegen" >&2
  exit 1
}

echo "==> Regenerating Xcode project from project.yml"
xcodegen generate

echo "==> Verifying the Apple Distribution identity is present"
if ! security find-identity -v -p codesigning | grep -q "Apple Distribution"; then
  echo "No 'Apple Distribution' signing identity found in the keychain." >&2
  echo "See docs/APPSTORE-SETUP.md step 1." >&2
  exit 1
fi

echo "==> Archiving ${SCHEME} (${CONFIG})"
rm -rf "${ARCHIVE_PATH}"
xcodebuild \
  -project "${SCHEME}.xcodeproj" \
  -scheme "${SCHEME}" \
  -configuration "${CONFIG}" \
  -archivePath "${ARCHIVE_PATH}" \
  archive

echo "==> Verifying the sandbox entitlement made it into the archive"
APP_PATH="${ARCHIVE_PATH}/Products/Applications/${SCHEME}.app"
if ! codesign -d --entitlements - --xml "${APP_PATH}" 2>/dev/null \
     | plutil -convert xml1 -o - - | grep -q "com.apple.security.app-sandbox"; then
  echo "FAIL: the archived app is not sandboxed. App Store upload will be rejected." >&2
  exit 1
fi
echo "    app-sandbox present"

echo ""
echo "==> Done: ${ARCHIVE_PATH}"
echo "    Opening Xcode Organizer. Use Distribute App -> App Store Connect."
open "${ARCHIVE_PATH}"
```

- [ ] **Step 2: Make it executable and run it**

```bash
cd /Users/lubosbury/DEV/OpenElswhere
chmod +x scripts/build-appstore.sh
./scripts/build-appstore.sh
```

Expected, in order:
```
==> Regenerating Xcode project from project.yml
==> Verifying the Apple Distribution identity is present
==> Archiving OpenElsewhere (ReleaseAppStore)
...
==> Verifying the sandbox entitlement made it into the archive
    app-sandbox present

==> Done: build/OpenElsewhere-AppStore.xcarchive
```

and Xcode Organizer opening with the archive selected.

If archiving fails with a provisioning error, the bundle ID has not been registered — that is step 3 of `docs/APPSTORE-SETUP.md`, and it is the user's action, not a code defect. Report it rather than working around it.

- [ ] **Step 3: Commit**

```bash
git add scripts/build-appstore.sh
git commit -m "Add App Store archive script with sandbox-entitlement guard"
```

---

### Task 7: Signed DMG script and release workflow

**Files:**
- Modify: `scripts/build-dmg.sh` (whole-file rewrite)
- Create: `.github/workflows/release.yml`

**Interfaces:**
- Consumes: the `Release` configuration (Task 2).
- Produces: `build/OpenElsewhere-<version>.dmg`, signed and optionally notarized, plus its SHA256 on stdout.

- [ ] **Step 1: Rewrite the DMG script to sign and optionally notarize**

Replace the entire contents of `scripts/build-dmg.sh` with:

```bash
#!/usr/bin/env bash
# Build a Developer ID-signed release DMG of OpenElsewhere.
#
# Usage: scripts/build-dmg.sh <version>
# Example: scripts/build-dmg.sh 1.0.0
#
# Environment:
#   NOTARIZE=1        Submit to Apple's notary service and staple the ticket.
#                     Requires ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH.
#   ASC_KEY_ID        App Store Connect API key ID.
#   ASC_ISSUER_ID     App Store Connect API issuer ID.
#   ASC_KEY_PATH      Path to the .p8 private key file.
#
# Produces build/OpenElsewhere-<version>.dmg and prints its SHA256.

set -euo pipefail

VERSION="${1:-}"
if [[ -z "${VERSION}" ]]; then
  echo "Usage: $0 <version>" >&2
  exit 2
fi

SCHEME="OpenElsewhere"
BUILD_DIR="build"
ARCHIVE_PATH="${BUILD_DIR}/${SCHEME}.xcarchive"
EXPORT_DIR="${BUILD_DIR}/export"
DMG_PATH="${BUILD_DIR}/OpenElsewhere-${VERSION}.dmg"

if [[ -z "${DEVELOPER_DIR:-}" ]] && [[ -d /Applications/Xcode.app ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

for tool in xcodegen create-dmg xcodebuild; do
  command -v "${tool}" >/dev/null || {
    echo "Missing dependency: ${tool}" >&2
    echo "  brew install xcodegen create-dmg" >&2
    exit 1
  }
done

echo "==> Regenerating Xcode project from project.yml"
xcodegen generate

echo "==> Archiving ${SCHEME} (Release, Developer ID signed)"
rm -rf "${ARCHIVE_PATH}"
xcodebuild \
  -project "${SCHEME}.xcodeproj" \
  -scheme "${SCHEME}" \
  -configuration Release \
  -archivePath "${ARCHIVE_PATH}" \
  archive

echo "==> Exporting .app from archive"
rm -rf "${EXPORT_DIR}"
mkdir -p "${EXPORT_DIR}"
cp -R "${ARCHIVE_PATH}/Products/Applications/${SCHEME}.app" "${EXPORT_DIR}/"

APP_PATH="${EXPORT_DIR}/${SCHEME}.app"

echo "==> Verifying the signature and hardened runtime"
codesign --verify --deep --strict --verbose=2 "${APP_PATH}"
codesign -dv --verbose=4 "${APP_PATH}" 2>&1 | grep -q "flags=.*runtime" || {
  echo "FAIL: hardened runtime is not enabled; notarization would be rejected." >&2
  exit 1
}

echo "==> Building DMG"
rm -f "${DMG_PATH}"
create-dmg \
  --volname "${SCHEME}" \
  --window-size 540 340 \
  --icon-size 100 \
  --icon "${SCHEME}.app" 140 170 \
  --hide-extension "${SCHEME}.app" \
  --app-drop-link 400 170 \
  "${DMG_PATH}" \
  "${EXPORT_DIR}/${SCHEME}.app"

if [[ "${NOTARIZE:-0}" == "1" ]]; then
  echo "==> Submitting to the notary service (this can take several minutes)"
  xcrun notarytool submit "${DMG_PATH}" \
    --key "${ASC_KEY_PATH}" \
    --key-id "${ASC_KEY_ID}" \
    --issuer "${ASC_ISSUER_ID}" \
    --wait

  echo "==> Stapling the notarization ticket"
  xcrun stapler staple "${DMG_PATH}"
  xcrun stapler validate "${DMG_PATH}"
else
  echo "==> Skipping notarization (set NOTARIZE=1 to enable)"
fi

echo ""
echo "==> Done"
echo "    DMG:    ${DMG_PATH}"
echo -n "    SHA256: "
shasum -a 256 "${DMG_PATH}" | awk '{print $1}'
```

- [ ] **Step 2: Create the release workflow**

Create `.github/workflows/release.yml`:

```yaml
name: Release DMG

on:
  push:
    tags:
      - "v*"

jobs:
  release:
    runs-on: macos-15
    permissions:
      contents: write

    steps:
      - uses: actions/checkout@v4

      - name: Derive version from tag
        id: version
        run: echo "value=${GITHUB_REF_NAME#v}" >> "$GITHUB_OUTPUT"

      - name: Install build tooling
        run: brew install xcodegen create-dmg

      - name: Import the Developer ID certificate
        env:
          CERT_P12_BASE64: ${{ secrets.DEVELOPER_ID_CERT_P12_BASE64 }}
          CERT_PASSWORD: ${{ secrets.CERT_PASSWORD }}
          KEYCHAIN_PASSWORD: ${{ secrets.KEYCHAIN_PASSWORD }}
        run: |
          CERT_PATH="$RUNNER_TEMP/cert.p12"
          KEYCHAIN_PATH="$RUNNER_TEMP/build.keychain-db"

          echo -n "$CERT_P12_BASE64" | base64 --decode -o "$CERT_PATH"

          security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
          security set-keychain-settings -lut 21600 "$KEYCHAIN_PATH"
          security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"

          security import "$CERT_PATH" -P "$CERT_PASSWORD" \
            -A -t cert -f pkcs12 -k "$KEYCHAIN_PATH"
          security set-key-partition-list -S apple-tool:,apple: \
            -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH" >/dev/null
          security list-keychain -d user -s "$KEYCHAIN_PATH"

          rm -f "$CERT_PATH"
          security find-identity -v -p codesigning "$KEYCHAIN_PATH"

      - name: Write the App Store Connect API key
        env:
          ASC_KEY_P8_BASE64: ${{ secrets.ASC_KEY_P8_BASE64 }}
        run: |
          echo -n "$ASC_KEY_P8_BASE64" | base64 --decode -o "$RUNNER_TEMP/asc.p8"

      - name: Build, sign, and notarize the DMG
        env:
          NOTARIZE: "1"
          ASC_KEY_ID: ${{ secrets.ASC_KEY_ID }}
          ASC_ISSUER_ID: ${{ secrets.ASC_ISSUER_ID }}
        run: |
          export ASC_KEY_PATH="$RUNNER_TEMP/asc.p8"
          chmod +x scripts/build-dmg.sh
          ./scripts/build-dmg.sh "${{ steps.version.outputs.value }}"

      - name: Compute the cask SHA256
        id: shasum
        run: |
          DMG="build/OpenElsewhere-${{ steps.version.outputs.value }}.dmg"
          echo "value=$(shasum -a 256 "$DMG" | awk '{print $1}')" >> "$GITHUB_OUTPUT"

      - name: Publish the GitHub release
        env:
          GH_TOKEN: ${{ github.token }}
        run: |
          gh release create "${GITHUB_REF_NAME}" \
            "build/OpenElsewhere-${{ steps.version.outputs.value }}.dmg" \
            --title "${GITHUB_REF_NAME}" \
            --generate-notes

      - name: Summarise the cask bump
        run: |
          {
            echo "## Homebrew cask bump"
            echo ""
            echo "Update \`Casks/openelsewhere.rb\` in the tap repo:"
            echo ""
            echo '```ruby'
            echo 'version "${{ steps.version.outputs.value }}"'
            echo 'sha256 "${{ steps.shasum.outputs.value }}"'
            echo '```'
          } >> "$GITHUB_STEP_SUMMARY"

      - name: Clean up the keychain
        if: always()
        run: |
          security delete-keychain "$RUNNER_TEMP/build.keychain-db" || true
          rm -f "$RUNNER_TEMP/asc.p8"
```

- [ ] **Step 3: Validate the workflow syntax**

```bash
cd /Users/lubosbury/DEV/OpenElswhere
python3 -c "import yaml,sys; yaml.safe_load(open('.github/workflows/release.yml')); print('YAML OK')"
```

Expected: `YAML OK`

- [ ] **Step 4: Verify the DMG script locally, without notarization**

This requires the `Developer ID Application` certificate from step 1a of `docs/APPSTORE-SETUP.md`. If it is absent, the archive step fails with a signing error — report it as a blocked prerequisite rather than working around it.

```bash
chmod +x scripts/build-dmg.sh
./scripts/build-dmg.sh 0.0.0-test
```

Expected tail:
```
==> Skipping notarization (set NOTARIZE=1 to enable)

==> Done
    DMG:    build/OpenElsewhere-0.0.0-test.dmg
    SHA256: <64 hex characters>
```

Confirm the signature is a real Developer ID one:

```bash
codesign -dv --verbose=4 build/export/OpenElsewhere.app 2>&1 | grep -E "Authority|flags"
```

Expected: an `Authority=Developer ID Application: Lubos Bury (78QQBJB52G)` line, and a `flags=` line containing `runtime`.

Then clean up the test artifact:

```bash
rm -f build/OpenElsewhere-0.0.0-test.dmg
```

- [ ] **Step 5: Commit**

```bash
git add scripts/build-dmg.sh .github/workflows/release.yml
git commit -m "Sign and notarize the DMG, add tag-triggered release workflow"
```

---

### Task 8: Documentation sweep

**Files:**
- Create: `PRIVACY.md`
- Modify: `RELEASING.md` (whole-file rewrite)
- Modify: `Casks/openelsewhere.rb`
- Modify: `README.md`

**Interfaces:**
- Consumes: everything above.
- Produces: no code.

- [ ] **Step 1: Write the privacy policy**

App Store Connect requires a privacy policy URL even when nothing is collected. Create `PRIVACY.md`:

```markdown
# Privacy Policy

**Last updated: 2026-08-11**

OpenElsewhere collects nothing.

## What the app stores

Your routing rules, your chosen default browser, and your chosen browser
profiles are stored in macOS `UserDefaults` on your own Mac. They are never
transmitted anywhere.

## What the app sends

Nothing. OpenElsewhere makes no network requests of its own — no analytics, no
crash reporting, no telemetry, no update checks.

The one exception is Apple's own StoreKit framework, used by the optional tip
jar in the Mac App Store version. If you choose to leave a tip, the transaction
is handled entirely by Apple. The developer receives no payment details and no
personally identifying information.

## URLs you open

OpenElsewhere sees the URLs it routes, because routing them is its purpose.
Those URLs are passed straight to the browser you configured and are never
logged, stored, or transmitted.

## Permissions

OpenElsewhere asks macOS for permission to send Apple Events to Arc and Dia.
This is used solely to open a link as a new tab in an existing window. It is
never used to read anything from those browsers.

## Contact

Questions: <lubos.bury@gmail.com>
```

- [ ] **Step 2: Remove the unsigned caveats from the cask**

In `Casks/openelsewhere.rb`, replace the entire `caveats` block with one that keeps only the Apple Events note:

```ruby
  caveats <<~EOS
    On first use of a rule that targets Arc or Dia, macOS will ask permission
    to control that app via Apple Events. Click OK to allow.
  EOS
```

Leave `version`, `sha256`, `url`, `name`, `desc`, `homepage`, `livecheck`, `depends_on macos: ">= :tahoe"`, `app`, and `zap` unchanged.

- [ ] **Step 3: Update the README install section**

In `README.md`:

1. In the **Install** section, replace the paragraph beginning "OpenElsewhere is a free, open-source utility. It is **not signed with an Apple Developer ID**…" with:

```markdown
OpenElsewhere is a free, open-source utility, available two ways: from the Mac App Store, or as a notarized DMG through Homebrew. Both are signed by the same developer account; neither needs a Gatekeeper workaround.
```

2. Replace the Homebrew command block so it no longer passes `--no-quarantine`:

```bash
brew tap lubosbury/openelsewhere
brew install --cask openelsewhere
```

3. Delete the entire **First launch on macOS** section, including the Gatekeeper block-quote and every `xattr -dr com.apple.quarantine` instruction. It is obsolete once the app is notarized.

4. In **Known limitations**, replace the line beginning "**Not sandboxed, not in the App Store**" with:

```markdown
- **The Mac App Store version cannot set itself as your default browser.** Apple does not allow sandboxed apps to change default handlers, so the app opens System Settings for you instead. The Homebrew version does it in one click.
- **The Mac App Store version does not list apps in `~/Applications` unless they are running.** The sandbox hides that directory. The Homebrew version sees everything.
```

5. Apply the same three edits to `OpenElsewhere/README.md`, which is a stale duplicate of this file.

- [ ] **Step 4: Rewrite RELEASING.md for both channels**

Replace the entire contents of `RELEASING.md` with:

```markdown
# Releasing OpenElsewhere

Two channels, released independently.

- **Mac App Store** — archived locally, uploaded through Xcode Organizer.
- **Homebrew DMG** — built, signed, and notarized by GitHub Actions on a tag.

One-time setup for both lives in [docs/APPSTORE-SETUP.md](docs/APPSTORE-SETUP.md).

---

## Mac App Store release

### 1. Bump the version

Edit `CFBundleShortVersionString` in `OpenElsewhere/Resources/Info.plist`.
Every App Store upload needs a build number higher than the last one.

### 2. Archive

```bash
./scripts/build-appstore.sh
```

This regenerates the project, verifies the `Apple Distribution` identity is
present, archives with the `ReleaseAppStore` configuration, asserts the sandbox
entitlement survived signing, and opens Xcode Organizer.

### 3. Upload

In Organizer: **Distribute App → App Store Connect → Upload**.

The first time, accept the prompt to create the Mac Installer Distribution
certificate.

### 4. Submit

Wait for the processing email, then in App Store Connect attach the build to
your version, complete the App Privacy questionnaire (nothing is collected),
paste the review notes from `docs/APPSTORE-SETUP.md` step 7, and submit.

---

## Homebrew DMG release

### 1. Tag and push

```bash
git tag v1.0.0
git push origin v1.0.0
```

That is the whole release. The `Release DMG` workflow then:

- imports the Developer ID certificate into a temporary keychain
- archives the `Release` configuration
- verifies the signature and hardened runtime
- builds the DMG
- notarizes it and staples the ticket
- creates the GitHub release with the DMG attached
- prints the cask `version` and `sha256` into the job summary

### 2. Bump the tap

Copy the two lines from the workflow's job summary into
`Casks/openelsewhere.rb` in your `homebrew-openelsewhere` tap repo:

```ruby
version "1.0.0"
sha256 "<from the job summary>"
```

```bash
cd ../homebrew-openelsewhere
git add Casks/openelsewhere.rb
git commit -m "openelsewhere 1.0.0"
git push
```

### 3. Smoke-test

```bash
brew uninstall --cask openelsewhere 2>/dev/null || true
brew untap lubosbury/openelsewhere 2>/dev/null || true

brew tap lubosbury/openelsewhere
brew install --cask openelsewhere
open /Applications/OpenElsewhere.app
```

No `--no-quarantine` — the app is notarized. If Gatekeeper still complains,
notarization or stapling failed; check the workflow log.

---

## Building a DMG locally

```bash
./scripts/build-dmg.sh 1.0.0
```

Signs with your local Developer ID certificate and skips notarization. To
notarize locally as well:

```bash
NOTARIZE=1 \
ASC_KEY_ID=XXXXXXXX \
ASC_ISSUER_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx \
ASC_KEY_PATH=~/keys/AuthKey_XXXXXXXX.p8 \
  ./scripts/build-dmg.sh 1.0.0
```

---

## Troubleshooting

**`xcodebuild` says it requires Xcode.**
`xcode-select` points at the Command Line Tools. Either run
`sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`, or rely on
the scripts, which set `DEVELOPER_DIR` themselves.

**Archive fails with a provisioning error.**
The bundle ID is not registered to the team, or the certificate is missing.
See `docs/APPSTORE-SETUP.md` steps 1 and 3.

**`build-appstore.sh` reports "the archived app is not sandboxed".**
`CODE_SIGN_ENTITLEMENTS` did not resolve for the `ReleaseAppStore`
configuration. Check the `configs:` block in `project.yml` and re-run
`xcodegen generate`.

**Notarization is rejected for hardened runtime.**
`ENABLE_HARDENED_RUNTIME` must be `YES` in the `base` settings of `project.yml`.

**App Review rejects the Apple Events entitlement.**
Reply in Resolution Center with the justification from
`docs/APPSTORE-SETUP.md` step 7 rather than resubmitting. If Apple holds firm,
remove `com.apple.security.temporary-exception.apple-events` from
`OpenElsewhere-AppStore.entitlements`; Arc and Dia then open links in a popup
instead of a tab, and every other browser is unaffected.
```

- [ ] **Step 5: Verify no stale instructions survive**

```bash
cd /Users/lubosbury/DEV/OpenElswhere
grep -rn "no-quarantine\|com.apple.quarantine\|not signed with an Apple Developer" \
  README.md RELEASING.md Casks/ OpenElsewhere/README.md
```

Expected: no output. Any match is a stale instruction that will mislead users once the app is notarized.

- [ ] **Step 6: Commit**

```bash
git add README.md OpenElsewhere/README.md RELEASING.md Casks/openelsewhere.rb PRIVACY.md
git commit -m "Document both distribution channels and add a privacy policy"
```

---

## Completion

After Task 8, confirm the whole thing still stands up:

```bash
cd /Users/lubosbury/DEV/OpenElswhere
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodegen generate
for CFG in Release ReleaseAppStore; do
  xcodebuild -project OpenElsewhere.xcodeproj -scheme OpenElsewhere \
    -configuration $CFG -derivedDataPath /tmp/oe-final-$CFG \
    CODE_SIGNING_ALLOWED=NO clean build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)"
done
grep -rn "#if APP_STORE" OpenElsewhere/Sources/ | grep -v Capabilities.swift
```

Expected: two `** BUILD SUCCEEDED **` lines, and **no output** from the `grep` — `#if APP_STORE` must appear only in `Capabilities.swift`.

Then remove the spike, which has served its purpose:

```bash
git rm -r spike/
git commit -m "Remove sandbox spike now that the real implementation is in place"
```

Open the pull request when the user asks for it.

## Out of scope

Tracked deliberately, not forgotten:

- **Liquid Glass redesign** — separate work, landing before the first App Store submission so store screenshots show the final design.
- **Preference migration between channels** — the user is the only user and accepts re-entering rules.
- **Rules export/import** — only worth building if migration becomes a real need.
- **Automated cask bumping** — a cross-repo token is not justified for a single-maintainer project.
- **Deleting the stale `OpenElsewhere/.git` duplicate clone** — housekeeping, unrelated to distribution.
