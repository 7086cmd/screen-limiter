#!/bin/zsh
# Builds build/Screen Limiter.app without an Xcode project.
#   ./build.sh            build + sign
#   ./build.sh --run      build, sign, (re)launch
set -euo pipefail
cd "${0:A:h}"

APP="build/Screen Limiter.app"
TARGET="arm64-apple-macos27.0"
IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development/{print $2; exit}')}"
IDENTITY="${IDENTITY:--}"   # fall back to ad-hoc

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc -O -target "$TARGET" -parse-as-library -swift-version 6 \
  -framework ScreenTime -framework ServiceManagement \
  -o "$APP/Contents/MacOS/ScreenLimiter" Sources/App/*.swift

swiftc -O -target "$TARGET" -swift-version 5 \
  -o "$APP/Contents/MacOS/ScreenLimiterHost" Sources/Host/main.swift

cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
../extension/build.sh >/dev/null
rsync -a --delete ../extension/dist/chrome/ "$APP/Contents/Resources/ChromeExtension/"
rsync -a --delete ../extension/dist/firefox/ "$APP/Contents/Resources/FirefoxExtension/"

codesign --force --options runtime --timestamp=none -s "$IDENTITY" "$APP/Contents/MacOS/ScreenLimiterHost"
codesign --force --options runtime --timestamp=none -s "$IDENTITY" "$APP"
echo "Built $APP (signed: $IDENTITY)"

if [[ "${1:-}" == "--run" ]]; then
  pkill -x ScreenLimiter 2>/dev/null || true
  sleep 0.5
  open "$APP"
fi
