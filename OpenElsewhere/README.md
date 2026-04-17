# OpenElsewhere

> Route links from specific macOS apps to the browser you actually want to use them in.

macOS lets you pick exactly **one** default browser. OpenElsewhere sits between that choice and the apps that open links, so you can say:

- "Links from Slack → open in **Arc** (Work space)"
- "Links from Mail → open in **Chrome** (Personal profile)"
- "Everything else → open in **Safari**"

It's a small menu-bar utility written in Swift + SwiftUI. No accounts, no background services, no telemetry — it just quietly forwards URLs to the right browser.

---

## Why this exists

I use Safari for personal browsing and Arc for work. I wanted the links from Slack to open in Arc without changing my system default — but macOS doesn't have a native way to do that. Tools like Finicky and Velja exist, but I wanted something simple, free, open-source, and native to the current macOS design language. So: OpenElsewhere.

---

## Features

- 🧭 **Per-app routing rules** — pick a source app, pick a target browser.
- 🪟 **Opens in your existing browser window** — new links appear as tabs, not new windows, even for Arc (which normally routes external links through its "Little Arc" popup).
- 🪪 **Optional browser-profile selection** — for Chromium (Chrome, Brave, Edge, Vivaldi, Opera) and Firefox. Useful for keeping work and personal contexts separated inside the same browser.
- 📎 **Menu bar + settings window** — no dock icon, quick toggle, full rule editor.
- 🎨 **Native look** — Liquid Glass design, adapts to light/dark mode with blue accents.
- 🔒 **No network, no analytics** — your rules live in `UserDefaults` on your Mac. Nothing leaves your machine.

---

## How it works

1. OpenElsewhere registers itself as the macOS default handler for `http` / `https` in its `Info.plist` (`CFBundleURLTypes` + `CFBundleDocumentTypes` with `public.html`, `public.url`).
2. When any app opens a URL, macOS delivers it to OpenElsewhere as an Apple Event (`kAEGetURL`).
3. The event carries the **sender's PID** in `keySenderPIDAttr`. We resolve that PID to a bundle identifier via `NSRunningApplication`.
4. That bundle ID is matched against your rules, and the URL is forwarded to the target browser — using the best launch strategy for that specific browser:

| Browser family | Launch strategy | Why |
|---|---|---|
| **Chrome / Brave / Edge / Vivaldi / Opera** | Run the binary directly with `--profile-directory=X` | Their binaries implement an IPC singleton — a second invocation forwards its args to the existing instance over a Unix socket. Profile switching works even while the browser is running. |
| **Arc / Dia** | AppleScript: `tell front window to make new tab` | Strictly single-instance. The binary refuses to start a second time. AppleScript also bypasses Arc's "Little Arc" popup and reuses your existing window. |
| **Firefox family** | Run the binary with `-P "ProfileName" --new-tab` | Firefox handles multi-launch via its own remote protocol. |
| **Safari / unknown** | `/usr/bin/open -b <bundle>` via LaunchServices | Safari has no profile CLI; this reuses the window cleanly. |
| **Any failure** | Falls back to `/usr/bin/open`, then `NSWorkspace.open` | Links always open — worst case in the system default. |

---

## Installation

There's no signed release yet — you build it from source with Xcode.

**Requirements**

- macOS 26 (Tahoe) or later
- Xcode 16 or later
- [`xcodegen`](https://github.com/yonsm/XcodeGen) (install with `brew install xcodegen`)

**Build**

```bash
git clone https://github.com/LubosBury/OpenElsewhere.git
cd OpenElsewhere
xcodegen generate            # regenerates OpenElsewhere.xcodeproj from project.yml
open OpenElsewhere.xcodeproj
```

Then in Xcode: **Product → Archive** (for a release build) or **⌘R** to run the debug build.

Drag the resulting `OpenElsewhere.app` to `/Applications`.

---

## Usage

1. Launch **OpenElsewhere**. A compass icon appears in the menu bar.
2. Click the icon → **Settings…**
3. Click **Make it Default** to register OpenElsewhere as your default link handler. (macOS will confirm the switch. Your old default browser is remembered by macOS and can be restored any time in **System Settings → Desktop & Dock → Default web browser**.)
4. Pick a **Default Browser** — the fallback when no rule matches (usually Safari).
5. Click **+ Add Rule** to create app-to-browser mappings.
6. Optionally pick a **profile** next to each rule (shown only for browsers that support them).

The first time a rule routes a link into Arc or Dia, macOS will ask:

> "OpenElsewhere" wants access to control "Arc".

Click **OK**. This lets OpenElsewhere tell Arc to open the URL as a new tab in your existing window.

---

## Known limitations

- **Profile switching on already-running Arc is not supported.** Arc is strictly single-instance and ignores command-line arguments on subsequent invocations. The URL goes to whichever Arc space is currently active. If you need hard "Slack → Arc Work space" routing, keep the Work space active, or use Chrome for that rule.
- **Some apps open URLs via helper processes.** When that happens the sender PID resolves to the helper rather than the parent app. The fallback is to use `NSWorkspace.shared.frontmostApplication`, which is correct for most user-initiated clicks.
- **macOS 26+ only** — the UI uses Liquid Glass APIs that aren't backported.
- **Not sandboxed, not in the App Store** — by design. The app needs to send Apple Events to other browsers, which requires the `com.apple.security.automation.apple-events` entitlement and rules out sandboxing.

---

## Project layout

```
OpenElsewhere/
├── project.yml                         # XcodeGen spec — source of truth
├── OpenElsewhere.xcodeproj/            # Generated; safe to regenerate any time
└── OpenElsewhere/
    ├── Sources/
    │   ├── OpenElsewhereApp.swift       # @main + MenuBarExtra + Settings window
    │   ├── AppDelegate.swift            # Apple Event → sender PID → route
    │   ├── RoutingEngine.swift          # Rules + persistence
    │   ├── BrowserLauncher.swift        # Per-browser launch strategies
    │   ├── BrowserDiscovery.swift       # Enumerate installed browsers / apps
    │   ├── BrowserProfile.swift         # Discover Chromium + Firefox profiles
    │   ├── MenuBarView.swift            # Menu bar UI
    │   ├── SettingsView.swift           # Settings window UI (Liquid Glass)
    │   ├── CompassLogo.swift            # Vector compass logo
    │   └── Models.swift                 # RoutingRule + AppInfo
    └── Resources/
        ├── Info.plist                   # URL-scheme handler declarations
        ├── OpenElsewhere.entitlements   # Automation entitlement
        └── Assets.xcassets              # App icon (compass, split blue tones)
```

Anytime you edit `project.yml` (adding files, changing settings), run `xcodegen generate` to refresh `OpenElsewhere.xcodeproj`.

---

## Contributing

Issues and PRs welcome! A few ideas that would be useful:

- Signed release builds / Homebrew Cask
- URL-pattern rules (e.g. `github.com` links always in Chrome regardless of source)
- Launch-at-login toggle (via `SMAppService`)
- Proper handling of Electron-style helper processes (walk up the process tree to the parent app)
- Icon and design polish

If you're adding a new browser, look at `BrowserCapabilities.forBundleID(_:)` in `BrowserProfile.swift` and `BrowserLauncher.swift` — most browsers slot into one of the existing families.

---

## Acknowledgements

Inspired by [Finicky](https://github.com/johnste/finicky) and [Velja](https://sindresorhus.com/velja). OpenElsewhere is narrower in scope (no config language, no URL patterns yet) but aims to feel more at home on modern macOS.

---

## License

[MIT](./LICENSE) — do whatever you want, no warranty.
