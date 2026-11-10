#!/bin/zsh
# Builds a signed, notarized Spider Pomodoro.dmg for people to download.
#
# Needs: Xcode signed in to the Apple Developer account (Xcode → Settings → Accounts)
# and XcodeGen. Uses the account's Developer ID certificate (Xcode creates it if needed)
# and Apple's notary service, so the app opens without warnings on other Macs.
#
# Usage: scripts/release-mac.sh        → build/release/SpiderPomodoro.dmg
set -euo pipefail

cd "$(dirname "$0")/.."
OUT=build/release
TEAM=$(awk '/DEVELOPMENT_TEAM:/ {print $2; exit}' project.yml)
rm -rf "$OUT" && mkdir -p "$OUT"

echo "› Generating project"
xcodegen generate --quiet

echo "› Archiving (Release)"
xcodebuild -project SpiderPomodoro.xcodeproj -scheme SpiderPomodoroMac -configuration Release \
  -destination 'generic/platform=macOS' -archivePath "$OUT/SpiderPomodoro.xcarchive" \
  -allowProvisioningUpdates -quiet archive

echo "› Signing with Developer ID and sending to Apple for notarization"
cat > "$OUT/ExportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key><string>developer-id</string>
    <key>destination</key><string>upload</string>
    <key>signingStyle</key><string>automatic</string>
    <key>teamID</key><string>$TEAM</string>
</dict>
</plist>
EOF
xcodebuild -exportArchive -archivePath "$OUT/SpiderPomodoro.xcarchive" \
  -exportOptionsPlist "$OUT/ExportOptions.plist" -exportPath "$OUT/upload" \
  -allowProvisioningUpdates -quiet

echo "› Waiting for Apple to notarize (usually under a few minutes)"
until xcodebuild -exportNotarizedApp -archivePath "$OUT/SpiderPomodoro.xcarchive" \
      -exportPath "$OUT/notarized" -allowProvisioningUpdates -quiet >/dev/null 2>&1; do
  sleep 20
done

APP="$OUT/notarized/Spider Pomodoro.app"
spctl --assess --type execute "$APP"
xcrun stapler validate "$APP" >/dev/null

echo "› Making the disk image"
mkdir "$OUT/dmg"
ditto "$APP" "$OUT/dmg/Spider Pomodoro.app"
ln -s /Applications "$OUT/dmg/Applications"
hdiutil create -volname "Spider Pomodoro" -srcfolder "$OUT/dmg" -ov -format UDZO -fs HFS+ \
  "$OUT/SpiderPomodoro.dmg" -quiet

VERSION=$(defaults read "$PWD/$APP/Contents/Info" CFBundleShortVersionString)
echo "✓ $OUT/SpiderPomodoro.dmg (version $VERSION)"
echo
echo "Publish it (installed apps see the update within a day):"
echo "  gh release create v$VERSION $OUT/SpiderPomodoro.dmg --title \"Spider Pomodoro $VERSION\" --notes \"What's new…\""
