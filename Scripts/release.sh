#!/usr/bin/env bash
# Builds the zip that goes on a GitHub release: signed with a Developer ID,
# notarized by Apple, and stapled, so it opens on someone else's Mac without a
# Gatekeeper warning.
#
#   DEVELOPER_ID="Developer ID Application: Your Name (TEAMID)" \
#   NOTARY_PROFILE=cleared-notary \
#   make dist
#
# DEVELOPER_ID    a certificate from `security find-identity -v -p codesigning`
# NOTARY_PROFILE  a credential profile saved once with
#                 `xcrun notarytool store-credentials <name>`
#
# Leave NOTARY_PROFILE unset to stop after signing. That zip runs on this Mac
# but Gatekeeper will refuse it anywhere else, so do not publish it.
set -euo pipefail

: "${DEVELOPER_ID:?Set DEVELOPER_ID to a Developer ID Application certificate — see the top of this script.}"
NOTARY_PROFILE=${NOTARY_PROFILE:-}

cd "$(git rev-parse --show-toplevel)"

team=${DEVELOPER_ID##*(}
team=${team%)}
version=$(sed -n 's/.*MARKETING_VERSION: *"\(.*\)".*/\1/p' project.yml)
app=build/Build/Products/Release/Cleared.app
zip=dist/Cleared-$version.zip

echo "▸ Building Cleared $version"
xcodegen generate >/dev/null
xcodebuild -project Cleared.xcodeproj -scheme Cleared -configuration Release \
  -derivedDataPath build \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$DEVELOPER_ID" \
  DEVELOPMENT_TEAM="$team" \
  OTHER_CODE_SIGN_FLAGS=--timestamp \
  clean build >/dev/null

echo "▸ Checking the signature"
codesign --verify --strict --deep "$app"
# Notarization rejects a build without the hardened runtime, and says so only
# after the upload. Fail here instead.
if ! codesign --display --verbose=2 "$app" 2>&1 | grep -q 'flags=.*runtime'; then
  echo "✖ $app was not signed with the hardened runtime." >&2
  exit 1
fi

mkdir -p dist
rm -f "$zip"
ditto -c -k --keepParent "$app" "$zip"

if [ -z "$NOTARY_PROFILE" ]; then
  echo "▸ NOTARY_PROFILE is not set — skipping notarization."
  echo "  $zip is signed but NOT notarized. Do not publish it."
  exit 0
fi

echo "▸ Notarizing (this waits on Apple, usually a minute or two)"
xcrun notarytool submit "$zip" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$app"

# The ticket is stapled to the app, so the zip has to be made again around it.
rm -f "$zip"
ditto -c -k --keepParent "$app" "$zip"

echo "▸ Asking Gatekeeper what it thinks"
spctl --assess --type execute --verbose=2 "$app"

echo "✓ $zip"
shasum -a 256 "$zip"
