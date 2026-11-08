#!/bin/bash
# Builds a release copy of Kai OS and packs it for download:
#   dist/Kai-OS.zip         the app, ad-hoc signed
#   dist/Kai-OS.zip.sha256  its checksum, checked by scripts/install.sh
# Upload both files to a GitHub release. This script does not publish anything.
set -euo pipefail

cd "$(dirname "$0")/.."

VERSION="$(plutil -extract CFBundleShortVersionString raw "Kai OS macOS/Info.plist")"
STAGE="dist/stage"
APP="$STAGE/Kai OS.app"
CONTENTS="$APP/Contents"

swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"

rm -rf dist
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
plutil -lint "Kai OS macOS/Info.plist"

cp "$BIN_DIR/Kai OS" "$CONTENTS/MacOS/Kai OS"
cp "$BIN_DIR/kai-hook" "$CONTENTS/MacOS/kai-hook"
cp "Kai OS macOS/Info.plist" "$CONTENTS/Info.plist"

# The app icon.
ICON_TMP="$(mktemp -d)"
xcrun actool Assets.xcassets --compile "$ICON_TMP" --platform macosx --minimum-deployment-target 14.0 \
    --app-icon AppIcon --output-partial-info-plist "$ICON_TMP/partial.plist" >/dev/null
cp "$ICON_TMP/AppIcon.icns" "$ICON_TMP/Assets.car" "$CONTENTS/Resources/"
rm -rf "$ICON_TMP"

# Ad-hoc signature: free, and enough for macOS to run it once the quarantine flag is cleared.
codesign --force --sign - --identifier ai.kai.hook "$CONTENTS/MacOS/kai-hook"
codesign --force --sign - --identifier ai.kai "$APP"
codesign --verify --deep --strict "$APP"

ditto -c -k --keepParent "$APP" dist/Kai-OS.zip
(cd dist && shasum -a 256 Kai-OS.zip > Kai-OS.zip.sha256)
rm -rf "$STAGE"

echo "Packed Kai OS $VERSION:"
ls -l dist
cat dist/Kai-OS.zip.sha256
