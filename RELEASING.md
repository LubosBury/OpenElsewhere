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

## Testing the tip jar locally

The App Store build's tip jar needs products to load. Before they exist in App
Store Connect, use the bundled StoreKit configuration:

**Product → Scheme → Edit Scheme… → Run → Options → StoreKit Configuration →
`OpenElsewhere/Resources/Products.storekit`**

That file is deliberately *not* a bundle resource — it is a local testing aid
and must never ship inside the app.

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

**Profile routing silently stops working in the App Store build.**
The helper script is missing or not executable. The Settings window shows the
"Enable profile routing" card whenever that is the case.

**App Review rejects the Apple Events entitlement.**
Reply in Resolution Center with the justification from
`docs/APPSTORE-SETUP.md` step 7 rather than resubmitting. If Apple holds firm,
remove `com.apple.security.temporary-exception.apple-events` from
`OpenElsewhere-AppStore.entitlements`; Arc and Dia then open links in a popup
instead of a tab, and every other browser is unaffected.
