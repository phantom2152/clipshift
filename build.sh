#!/bin/bash
# Builds ClipShift.app (Command Line Tools are enough, no Xcode needed) and launches it.
#   ./build.sh                          ad-hoc signature
#   SIGN_ID="ClipBar Dev" ./build.sh    sign with a self-signed cert
#   NO_LAUNCH=1 ./build.sh              build only, don't open
set -euo pipefail
cd "$(dirname "$0")"

NAME="ClipShift"
APP="$NAME.app"
SIGN_ID="${SIGN_ID:--}"

swift build -c release
BIN="$(swift build -c release --show-bin-path)/$NAME"

# Stop the running copy and wait until it is really gone (avoids LaunchServices error -600)
pkill -x "$NAME" 2>/dev/null || true
while pgrep -x "$NAME" >/dev/null; do sleep 0.1; done

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$NAME"

# Icon is optional: drop Resources/AppIcon.icns in place and it gets picked up.
ICON_KEY=""
if [ -f Resources/AppIcon.icns ]; then
  cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
  ICON_KEY="<key>CFBundleIconFile</key><string>AppIcon</string>"
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>dev.anish.clipshift</string>
  <key>CFBundleName</key><string>ClipShift</string>
  <key>CFBundleDisplayName</key><string>ClipShift</string>
  <key>CFBundleExecutable</key><string>ClipShift</string>
  ${ICON_KEY}
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.video</string>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>CFBundleDocumentTypes</key>
  <array><dict>
    <key>CFBundleTypeName</key><string>Media</string>
    <key>CFBundleTypeRole</key><string>Viewer</string>
    <key>LSHandlerRank</key><string>Alternate</string>
    <key>LSItemContentTypes</key>
    <array><string>public.movie</string><string>public.audio</string></array>
  </dict></array>
</dict></plist>
PLIST

codesign --force --sign "$SIGN_ID" "$APP"

if [ "${NO_LAUNCH:-0}" != "1" ]; then
  sleep 0.5
  open "$APP"
  echo "Launched $APP"
else
  echo "Built $APP"
fi
