#!/usr/bin/env bash
# Archives Cleared for the Mac App Store and exports the signed package that
# App Store Connect accepts.
#
#   make appstore
#
# Needs CLEARED_APPSTORE_TEAM in Local.xcconfig (see Local.xcconfig.example)
# and that team's Apple ID signed in to Xcode → Settings → Accounts. Xcode
# registers the bundle ID and creates the App Store provisioning profile the
# first time this runs.
#
# The archive is written where Xcode's Organizer looks, so the same build can
# be uploaded from Window → Organizer → Distribute App. Nothing is uploaded
# here.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"
xcodegen generate >/dev/null

setting() {
  xcodebuild -project Cleared.xcodeproj -scheme Cleared -configuration AppStore -showBuildSettings 2>/dev/null \
    | sed -n "s/^ *$1 = //p" | head -1
}

team=$(setting DEVELOPMENT_TEAM)
version=$(setting MARKETING_VERSION)
build=$(setting CURRENT_PROJECT_VERSION)
if [ -z "$team" ]; then
  echo "✖ No App Store team. Set CLEARED_APPSTORE_TEAM in Local.xcconfig — see Local.xcconfig.example." >&2
  exit 1
fi

archive="$HOME/Library/Developer/Xcode/Archives/$(date +%Y-%m-%d)/Cleared $version ($build) $(date +%H.%M).xcarchive"
out=dist/appstore
options=build/ExportOptions.plist

echo "▸ Archiving Cleared $version ($build) with the AppStore configuration"
mkdir -p "$(dirname "$archive")" build
xcodebuild archive -project Cleared.xcodeproj -scheme Cleared \
  -archivePath "$archive" -allowProvisioningUpdates >build/appstore-archive.log 2>&1 \
  || { tail -25 build/appstore-archive.log >&2; exit 1; }

cat >"$options" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key>
	<string>app-store-connect</string>
	<key>destination</key>
	<string>export</string>
	<key>signingStyle</key>
	<string>automatic</string>
	<key>teamID</key>
	<string>$team</string>
</dict>
</plist>
PLIST

echo "▸ Exporting, signed for the App Store"
rm -rf "$out"
xcodebuild -exportArchive -archivePath "$archive" -exportOptionsPlist "$options" \
  -exportPath "$out" -allowProvisioningUpdates >build/appstore-export.log 2>&1 \
  || { tail -25 build/appstore-export.log >&2; exit 1; }

pkg=$(ls "$out"/*.pkg | head -1)
echo "▸ Checking what was produced"
pkgutil --check-signature "$pkg" | sed -n '1,6p'

# Unpack the app from the package and confirm it is what the store requires:
# sandboxed, signed for distribution, and without the debugger entitlement
# that development builds carry.
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
pkgutil --expand-full "$pkg" "$work/pkg" >/dev/null
app=$(find "$work/pkg" -maxdepth 4 -name 'Cleared.app' | head -1)
entitlements=$(codesign --display --entitlements - --xml "$app" 2>/dev/null | plutil -convert json -o - - 2>/dev/null || echo '{}')
case "$entitlements" in
  *'"com.apple.security.app-sandbox":true'*) ;;
  *) echo "✖ The exported app is not sandboxed." >&2; exit 1 ;;
esac
case "$entitlements" in
  *get-task-allow*) echo "✖ The exported app still has get-task-allow." >&2; exit 1 ;;
esac
codesign --verify --strict --deep "$app"

echo "✓ $pkg"
echo "  Archive: $archive"
echo "  Upload it from Xcode's Organizer, or with Transporter."
