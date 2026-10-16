#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")"

APP=build/MchoseBar.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

swiftc -O -swift-version 5 -target arm64-apple-macos14.0 \
  -framework AppKit -framework SwiftUI -framework IOKit \
  -parse-as-library Sources/Core/*.swift Sources/App/*.swift Sources/UI/*.swift -o "$APP/Contents/MacOS/MchoseBar"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>local.mchosebar</string>
  <key>CFBundleName</key><string>MchoseBar</string>
  <key>CFBundleExecutable</key><string>MchoseBar</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

# fixed cert so Input Monitoring permission survives rebuilds
IDENTITY=$(security find-identity -p codesigning | awk '/"MchoseBar Dev"/{print $2; exit}')
if [[ -z "$IDENTITY" ]]; then
  echo "no 'MchoseBar Dev' cert, signing ad-hoc (Input Monitoring resets every build)"
  IDENTITY=-
fi
# iCloud Desktop keeps re-adding xattrs that break codesign
for i in 1 2 3 4 5; do
  xattr -cr "$APP"
  codesign --force --sign "$IDENTITY" "$APP" 2>/dev/null && break
  [[ $i == 5 ]] && { echo "codesign failed"; exit 1 }
  sleep 0.5
done
echo "OK: $APP"
