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
