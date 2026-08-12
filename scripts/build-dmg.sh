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

# Capture first, then match. Piping straight into `grep -q` under `pipefail`
# fails spuriously: grep exits on the first match, closes the pipe, and
# codesign dies of SIGPIPE, which pipefail then reports as pipeline failure.
CODESIGN_INFO="$(codesign -dv --verbose=4 "${APP_PATH}" 2>&1 || true)"
if ! printf '%s' "${CODESIGN_INFO}" | grep -q "flags=.*runtime"; then
  echo "FAIL: hardened runtime is not enabled; notarization would be rejected." >&2
  exit 1
fi
if ! printf '%s' "${CODESIGN_INFO}" | grep -q "Authority=Developer ID Application"; then
  echo "FAIL: not signed with a Developer ID Application certificate." >&2
  exit 1
fi
echo "    hardened runtime and Developer ID signature confirmed"

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
