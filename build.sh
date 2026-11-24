#!/bin/bash
# 编译并打包 Glance.app（无需 Xcode，只用 Command Line Tools）
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Glance"
BUILD_DIR="build"
APP="$BUILD_DIR/$APP_NAME.app"
ARCH="$(uname -m)"

rm -rf "$BUILD_DIR"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "==> 编译 Swift 源码"
swiftc -O -swift-version 5 \
  -target "${ARCH}-apple-macosx13.0" \
  -framework Cocoa -framework IOKit -framework ServiceManagement \
  Sources/*.swift \
  -o "$APP/Contents/MacOS/$APP_NAME"

echo "==> 写入 Info.plist"
cp Info.plist "$APP/Contents/Info.plist"

if [ -f Resources/AppIcon.icns ]; then
  cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
  /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$APP/Contents/Info.plist" 2>/dev/null || true
fi

echo "==> 临时签名（ad-hoc）"
codesign --force --sign - --timestamp=none "$APP" >/dev/null 2>&1

echo "==> 完成：$APP  ($(du -sh "$APP" | cut -f1))"
