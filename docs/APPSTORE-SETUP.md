# OpenElsewhere — Manual Setup Runbook

Everything that must be done by hand, outside the codebase, to publish
OpenElsewhere on the Mac App Store and to notarize the Homebrew DMG.

Do these **in order**. Steps 1–3 block implementation work; steps 4–9 can happen
while the code is being written.

**Your details**

| | |
|---|---|
| Team ID | `78QQBJB52G` |
| Apple ID | `lubos.bury@gmail.com` |
| Bundle ID | `com.openelsewhere.app` |
| Existing certificate | `Apple Distribution: Lubos Bury` ✅ |

Apple moves its web UI around regularly. Where a path below no longer matches,
the labels are still the right things to search for.

---

## 1. Create the missing certificates

You have `Apple Distribution` (App Store). You are missing two.

### 1a. Developer ID Application — required for the notarized DMG

Easiest route is Xcode, which handles the certificate signing request for you:

**Xcode → Settings → Accounts →** select your Apple ID **→ Manage Certificates… →
`+` → Developer ID Application**

> Only the Account Holder can create these, and the team is limited to a small
> number of them. If the `+` menu doesn't offer it, confirm you're the Account
> Holder at [developer.apple.com/account](https://developer.apple.com/account).

Verify it landed:

```bash
security find-identity -v -p codesigning | grep "Developer ID Application"
```

### 1b. Mac Installer Distribution — required for App Store upload

You do **not** need to create this manually. Xcode Organizer generates it the
first time you run **Distribute App → App Store Connect**. Just accept the prompt.

### 1c. Export the Developer ID certificate for CI

The GitHub Actions workflow needs it as a base64 `.p12`.

**Keychain Access → login keychain → My Certificates →** right-click
*Developer ID Application: Lubos Bury (78QQBJB52G)* **→ Export…** → save as
`developerID.p12`, set a strong password (you'll need it in step 8).

Then:

```bash
base64 -i developerID.p12 | pbcopy
```

That's now on your clipboard for step 8. **Delete the `.p12` afterwards** — do not
commit it, and do not leave it in Downloads.

---

## 2. Create an App Store Connect API key

Used for notarization in CI. Preferred over an app-specific password because it
survives password changes and can be revoked independently.

**[App Store Connect](https://appstoreconnect.apple.com) → Users and Access →
Integrations → App Store Connect API → Team Keys → `+`**

- **Name:** `OpenElsewhere CI`
- **Access:** `Developer`

Download the `.p8` file. **Apple lets you download it exactly once.**

Record three values:

| Value | Where |
|---|---|
| Key ID | shown in the keys table |
| Issuer ID | shown above the keys table |
| The `.p8` file | your one-time download |

```bash
base64 -i AuthKey_XXXXXXXX.p8 | pbcopy
```

Store the `.p8` in your password manager, then delete it from disk.

---

## 3. Register the bundle identifier

**[developer.apple.com/account](https://developer.apple.com/account) →
Certificates, Identifiers & Profiles → Identifiers → `+` → App IDs → App**

- **Description:** `OpenElsewhere`
- **Bundle ID:** Explicit → `com.openelsewhere.app`
- **Capabilities:** enable **In-App Purchase**. Nothing else is needed — App
  Sandbox and Apple Events are entitlement-file concerns, not capability
  toggles.

If the identifier already exists from earlier experimentation, just edit it to
enable In-App Purchase.

---

## 4. Write and host a privacy policy

App Store Connect **requires a privacy policy URL** even for apps that collect
nothing. OpenElsewhere genuinely collects nothing — everything lives in
`UserDefaults` on the user's Mac.

Simplest approach: commit a `PRIVACY.md` to the repo and use its rendered GitHub
URL:

```
https://github.com/LubosBury/OpenElsewhere/blob/main/PRIVACY.md
```

It needs to state, honestly and briefly: no data collection, no analytics, no
network requests except Apple's own StoreKit for tips, and that routing rules
never leave the device.

---

## 5. Create the App Store Connect app record

**App Store Connect → Apps → `+` → New App**

| Field | Value |
|---|---|
| Platforms | macOS |
| Name | `OpenElsewhere` |
| Primary language | English (U.S.) |
| Bundle ID | `com.openelsewhere.app` |
| SKU | `OPENELSEWHERE001` (internal only, never shown) |
| User Access | Full Access |

> **If the name is taken**, you must pick another — App Store names are globally
> unique. Find out now rather than at submission.

Then fill in **App Information**:

- **Category:** Utilities (primary). Productivity is a reasonable secondary.
- **Privacy Policy URL:** from step 4
- **Content Rights:** does not contain third-party content
- **Age Rating:** answer all "None" → results in 4+

All the user-facing text — subtitle, promotional text, description, keywords,
what's new — is written and length-checked in
[Appendix A](#appendix-a--store-listing-copy-paste-ready). Paste from there.

And **Pricing and Availability**:

- **Price:** Free
- **Availability:** all territories

---

## 6. Create the in-app purchase products

**Your app record → Monetization → In-App Purchases → `+`**

Create three, all of type **Consumable**. Every field below is within Apple's
character limits — **Display Name** caps at 30 and **Description** at 45, and
App Store Connect silently truncates or refuses longer text.

| Product ID | Reference Name | Display Name | Description (≤45) | Price |
|---|---|---|---|---|
| `com.openelsewhere.app.tip.small` | Small Tip | `Small Tip` | `A small thank you. Unlocks nothing.` | Tier 2 |
| `com.openelsewhere.app.tip.medium` | Medium Tip | `Medium Tip` | `A generous thank you. Unlocks nothing.` | Tier 5 |
| `com.openelsewhere.app.tip.large` | Large Tip | `Large Tip` | `A very generous tip. Unlocks nothing.` | Tier 10 |

Each one also needs:

- **Review Screenshot** — a screenshot of the tip menu in the app. Required, and
  a common cause of IAP rejection when omitted.
- **Review Notes** — `Optional tip. Grants no functionality; the app is fully free.`

> Prefer a single tier? It's a one-line change in `TipJar.productIDs` plus one
> App Store Connect record instead of three.

IAPs are reviewed alongside your first submission, so they must be in **Ready to
Submit** state before you submit the build.

---

## 7. Prepare screenshots and the review notes

### Screenshots

At least one, up to ten, at one of these exact sizes:

`1280×800` · `1440×900` · `2560×1600` · `2880×1800`

`2880×1800` on a Retina display is the easiest to produce. Capture with
`⌘⇧4` then `Space` to grab a window, and check the pixel dimensions.

Worth showing: the menu-bar popover, the rules list with a couple of realistic
rules, and the settings window.

### Review notes — the part that decides your approval

OpenElsewhere is unusual in three ways a reviewer will not guess: it has no dock
icon, it does nothing until it becomes the default browser, and it requests an
Apple Events exception. Say all of it explicitly.

Draft to adapt:

> OpenElsewhere is a menu-bar utility (LSUIElement) — it has no Dock icon and no
> main window. After launch, its icon appears in the menu bar at the top right of
> the screen.
>
> **To test the app's core function:**
> 1. Launch OpenElsewhere. A compass icon appears in the menu bar.
> 2. Open System Settings → Desktop & Dock → Default web browser, and select
>    OpenElsewhere. (The app cannot set this itself under App Sandbox, so it
>    guides the user to this setting.)
> 3. Click the menu-bar icon → Settings, and add a rule: choose a source app
>    (for example Mail) and a destination browser (for example Safari).
> 4. Click any http/https link inside that source app. OpenElsewhere receives the
>    URL and opens it in the browser chosen by the rule.
>
> **Regarding the `com.apple.security.temporary-exception.apple-events`
> entitlement:** it is limited to exactly two bundle identifiers,
> `company.thebrowser.Browser` (Arc) and `company.thebrowser.dia` (Dia). These
> two browsers refuse to launch a second process instance and, when they receive
> a URL through LaunchServices, open it in a detached popup window rather than a
> tab. A single Apple Event asking the browser to make a new tab in its front
> window is the only way to deliver the tab behavior users expect. The
> entitlement is not used for any other purpose or any other application, and
> macOS still requires the user to grant automation permission on first use.
>
> **In-app purchases** are optional tips only. They unlock no functionality; the
> app is fully functional for free.

---

## 8. Add the GitHub Actions secrets

**Repo → Settings → Secrets and variables → Actions → New repository secret**

| Secret | Value |
|---|---|
| `DEVELOPER_ID_CERT_P12_BASE64` | base64 from step 1c |
| `CERT_PASSWORD` | the `.p12` export password from step 1c |
| `KEYCHAIN_PASSWORD` | any strong random string you invent now |
| `ASC_KEY_ID` | Key ID from step 2 |
| `ASC_ISSUER_ID` | Issuer ID from step 2 |
| `ASC_KEY_P8_BASE64` | base64 of the `.p8` from step 2 |

---

## 9. Submit

Once the implementation is done:

```bash
./scripts/build-appstore.sh
```

Then in the Xcode Organizer window it opens:

1. **Distribute App → App Store Connect → Upload**
2. Accept the prompt to create the Mac Installer Distribution certificate
3. Wait for the "processing" email — usually 5–30 minutes
4. In App Store Connect, attach the processed build to your version
5. Complete the **App Privacy** questionnaire — answer "No" to data collection
   throughout; OpenElsewhere collects nothing
6. Paste the review notes from step 7
7. **Add for Review → Submit**

First review typically takes 24–48 hours.

### If it's rejected

The likely cause is the Apple Events entitlement. Reviewers sometimes reject it
on a first pass and accept it after a reply in Resolution Center that restates the
justification from step 7 more concretely. Reply rather than resubmitting — it's
faster and keeps you in the same review thread.

The fallback, if Apple holds firm: drop the exception entitlement from the App
Store build only. Arc and Dia then open links in a popup window instead of a tab.
Every other browser is unaffected, and the DMG build keeps the better behavior.

---

## Local prerequisite

The DMG script needs a tool you don't currently have installed:

```bash
brew install create-dmg
```

---

## Appendix A — Store listing copy (paste-ready)

Every length-capped field below has been counted against Apple's limit. Where a
field is capped, the cap is in the heading and the actual count is noted.

### App Name — 13/30

```
OpenElsewhere
```

### Subtitle — 25/30

```
Right link, right browser
```

Alternates, if you prefer a different angle:

| Subtitle | Count |
|---|---|
| `Per-app browser routing` | 23/30 |
| `Links open where you want` | 25/30 |

Note the subtitle is indexed for search alongside the name, so the words
"link" and "browser" are already covered and should **not** be repeated in
keywords.

### Promotional Text — 154/170

Editable any time **without** a new review, unlike the description. Good place
to announce things later.

```
Slack links in Chrome. Mail links in Safari. Set a rule once and every app sends its links exactly where you want — no more copying URLs between browsers.
```

### Keywords — 98/100

```
default,url,routing,chromium,profiles,menubar,productivity,tabs,work,switcher,handler,picker,links
```

> **Deliberately avoids competitor brand names.** A keyword list naming Chrome,
> Safari, Firefox, Arc, Brave, and Edge scores better on search but is a
> recognised rejection risk: Apple's metadata rules disallow third-party
> trademarks you don't own, and keywords are where reviewers look hardest.
> Brand names inside the *description*, used to describe genuine
> interoperability, are far safer and are used below.
>
> If you want to gamble on the higher-traffic version, this is it (95/100) —
> but expect a possible metadata rejection:
> `default,url,routing,chrome,profile,safari,arc,firefox,edge,brave,menubar,productivity,tabs,work`

### Description — ~1,700/4,000

```
OpenElsewhere sends every link to the browser you actually want.

Set it as your default browser once, then write simple rules: links from Slack open in Chrome, links from Mail open in Safari, and everything else falls back to whatever you choose. No more pasting URLs between browsers.

WHAT IT DOES

• Per-app rules — pick a source app, pick the browser its links should open in
• Browser profiles — send work links to your work profile and personal links to your personal one, on Chromium-based browsers and Firefox
• Lives in the menu bar — no Dock icon, nothing in your way
• Sensible fallback — anything without a rule goes to your chosen default browser
• One switch to pause routing entirely

WHY

If you keep work and personal browsing separate, macOS gives you exactly one default browser and no say in the matter. OpenElsewhere puts that decision back where it belongs: with the app the link came from.

PRIVACY

OpenElsewhere collects nothing. No analytics, no telemetry, no accounts, and no network requests of its own. Your rules stay on your Mac. The URLs it routes are handed straight to your browser and are never logged or transmitted.

FREE, AND OPEN SOURCE

The complete source is on GitHub. The optional tips inside the app unlock nothing — every feature is free, permanently.

TWO THINGS TO KNOW

App Store apps run sandboxed, so two steps need your hand:

• You set OpenElsewhere as your default browser in System Settings. The app opens the right pane for you.
• Routing to a specific browser profile needs a small helper script you install once. The app walks you through it, and links still reach the right browser without it.
```

### What's New — first release

```
First release.

• Route links from any app to any browser, with per-app rules
• Target a specific browser profile on Chromium-based browsers and Firefox
• Arc and Dia links open as a tab in your existing window, not a popup
• Lives in the menu bar, collects nothing, free and open source
```

### URLs and copyright

| Field | Value |
|---|---|
| Privacy Policy URL | `https://github.com/LubosBury/OpenElsewhere/blob/main/PRIVACY.md` |
| Support URL | `https://github.com/LubosBury/OpenElsewhere/issues` |
| Marketing URL | `https://github.com/LubosBury/OpenElsewhere` |
| Copyright | `2026 Lubos Bury` |

### Screenshot captions

macOS screenshots carry no caption field — whatever text appears must be baked
into the image, and plain unannotated screenshots are perfectly acceptable.
Three that tell the story in order:

1. **The settings window with two or three realistic rules** — Slack → Chrome
   (Work profile), Mail → Safari. This is the whole product in one image; make
   it screenshot #1, since it's the only one many people see.
2. **The menu bar popover open**, showing the app is out of the way.
3. **The rule editor mid-edit**, with the browser picker open and profiles
   visible.

Use realistic app names, not `Test App 1`. Reviewers and users both read them.

---

## Checklist

- [ ] 1a. Developer ID Application certificate created
- [ ] 1c. `.p12` exported and base64-copied
- [ ] 2. App Store Connect API key created, `.p8` saved to password manager
- [ ] 3. Bundle ID registered with In-App Purchase enabled
- [x] 4. `PRIVACY.md` written and pushed — live at
      `https://github.com/LubosBury/OpenElsewhere/blob/main/PRIVACY.md`
- [ ] 5. App record created, name confirmed available (copy in Appendix A)
- [ ] 6. Three consumable IAPs created with review screenshots
- [ ] 7. Screenshots captured, review notes drafted
- [ ] 8. Six GitHub secrets added
- [ ] 9. Build uploaded and submitted
