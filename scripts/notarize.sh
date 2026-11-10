#!/bin/bash
# Signs Kai OS with a Developer ID certificate, has Apple notarize it, and staples the ticket, so a downloaded copy
# opens without the "Apple could not verify" warning. It needs a paid Apple Developer account. This script publishes
# nothing: it makes dist/Kai-OS-<version>.dmg for you to upload.
#
#   scripts/notarize.sh check     says what is missing, and changes nothing
#   scripts/notarize.sh           builds, signs, notarizes and staples
#
# One-time setup (see NOTARIZATION.md):
#   1. A "Developer ID Application" certificate in your keychain (Xcode > Settings > Accounts > Manage Certificates).
#   2. A saved notarytool login. The password is an app-specific password from appleid.apple.com, entered by you:
#        xcrun notarytool store-credentials kai-notary --apple-id YOU@EXAMPLE.COM --team-id TEAMID
#      Override the profile name with KAI_NOTARY_PROFILE.
set -euo pipefail
cd "$(dirname "$0")/.."

PROFILE="${KAI_NOTARY_PROFILE:-kai-notary}"
IDENTITY="${KAI_DEVELOPER_ID:-$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Developer ID Application/ {print $2; exit}')}"
missing=0

echo "Checking what notarizing needs:"
if [ -n "$IDENTITY" ]; then echo "  ok       Developer ID certificate: $IDENTITY"
else echo "  MISSING  a \"Developer ID Application\" certificate in your keychain"; missing=1; fi

if xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1; then echo "  ok       notarytool login \"$PROFILE\""
else echo "  MISSING  a saved notarytool login named \"$PROFILE\" (xcrun notarytool store-credentials $PROFILE --apple-id ... --team-id ...)"; missing=1; fi

if command -v hdiutil >/dev/null && command -v xcrun >/dev/null; then echo "  ok       hdiutil and xcrun"; else echo "  MISSING  Xcode command line tools"; missing=1; fi

if [ "${1:-}" = "check" ]; then
    [ "$missing" = 0 ] && echo "Everything is in place. Run scripts/notarize.sh." || echo "Not ready yet. Nothing was changed."
    exit "$missing"
fi
[ "$missing" = 0 ] || { echo "Not ready. Run scripts/notarize.sh check, fix what is MISSING, and try again."; exit 1; }

VERSION="$(plutil -extract CFBundleShortVersionString raw "Kai OS macOS/Info.plist")"
STAGE="dist/notarize"
APP="$STAGE/Kai OS.app"
CONTENTS="$APP/Contents"

swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"
rm -rf "$STAGE"; mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
cp "$BIN_DIR/Kai OS" "$CONTENTS/MacOS/Kai OS"
cp "$BIN_DIR/kai-hook" "$CONTENTS/MacOS/kai-hook"
cp "Kai OS macOS/Info.plist" "$CONTENTS/Info.plist"
ICON_TMP="$(mktemp -d)"
xcrun actool Assets.xcassets --compile "$ICON_TMP" --platform macosx --minimum-deployment-target 14.0 \
    --app-icon AppIcon --output-partial-info-plist "$ICON_TMP/partial.plist" >/dev/null
cp "$ICON_TMP/AppIcon.icns" "$ICON_TMP/Assets.car" "$CONTENTS/Resources/"; rm -rf "$ICON_TMP"

# Hardened runtime and a secure timestamp are what notarization requires. The helper is signed first, then the app.
codesign --force --timestamp --options runtime --sign "$IDENTITY" --identifier ai.kai.hook "$CONTENTS/MacOS/kai-hook"
codesign --force --timestamp --options runtime --sign "$IDENTITY" --identifier ai.kai --entitlements ai.kai.entitlements "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

DMG="dist/Kai-OS-$VERSION.dmg"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Kai OS" -fs APFS -format UDZO -srcfolder "$STAGE" -o "$DMG" >/dev/null
codesign --force --timestamp --sign "$IDENTITY" "$DMG"

xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
rm -rf "$STAGE"
(cd dist && shasum -a 256 "Kai-OS-$VERSION.dmg" > "Kai-OS-$VERSION.dmg.sha256")
echo "Done: $DMG"
