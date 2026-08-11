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

And **Pricing and Availability**:

- **Price:** Free
- **Availability:** all territories

---

## 6. Create the in-app purchase products

**Your app record → Monetization → In-App Purchases → `+`**

Create three, all of type **Consumable**:

| Product ID | Reference Name | Suggested price |
|---|---|---|
| `com.openelsewhere.app.tip.small` | Small Tip | Tier 2 |
| `com.openelsewhere.app.tip.medium` | Medium Tip | Tier 5 |
| `com.openelsewhere.app.tip.large` | Large Tip | Tier 10 |

Each one needs:

- **Display Name** and **Description** — user-visible, e.g. *"Support ongoing
  development of OpenElsewhere. This is a tip; it unlocks nothing."*
- **Review Screenshot** — a screenshot of your tip-jar UI. Required, and a common
  cause of IAP rejection when omitted.
- **Review Notes** — *"Optional tip. Grants no functionality; the app is fully
  free."*

> Tell me if you'd rather ship a single tip tier instead of three — it's a
> one-line change in the implementation, and three separate IAP records is real
> paperwork.

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

## Checklist

- [ ] 1a. Developer ID Application certificate created
- [ ] 1c. `.p12` exported and base64-copied
- [ ] 2. App Store Connect API key created, `.p8` saved to password manager
- [ ] 3. Bundle ID registered with In-App Purchase enabled
- [ ] 4. `PRIVACY.md` written and pushed
- [ ] 5. App record created, name confirmed available
- [ ] 6. Three consumable IAPs created with review screenshots
- [ ] 7. Screenshots captured, review notes drafted
- [ ] 8. Six GitHub secrets added
- [ ] 9. Build uploaded and submitted
