#!/bin/bash
# 编译并打包 Glance.app（无需 Xcode，只用 Command Line Tools）
# 产物为通用二进制（arm64 + x86_64），Intel 与 Apple Silicon 都能运行
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Glance"
MIN_VER="13.0"
BUILD_DIR="build"
APP="$BUILD_DIR/$APP_NAME.app"
SOURCES=(Sources/*.swift)
FRAMEWORKS=(-framework Cocoa -framework IOKit -framework ServiceManagement)

rm -rf "$BUILD_DIR"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$BUILD_DIR/obj"

echo "==> 编译 Swift 源码（通用二进制）"
BINARIES=()
for ARCH in arm64 x86_64; do
  echo "    - ${ARCH}"
  echo "    - C 模块 (${ARCH})"
  clang -O2 -target "${ARCH}-apple-macos${MIN_VER}" -c Sources/c/ioreport.c \
    -o "$BUILD_DIR/obj/ioreport-$ARCH.o"
  clang -O2 -target "${ARCH}-apple-macos${MIN_VER}" -c Sources/c/procs.c \
    -o "$BUILD_DIR/obj/procs-$ARCH.o"
  swiftc -O -swift-version 5 \
    -target "${ARCH}-apple-macosx13.0" \
    "${FRAMEWORKS[@]}" \
    "${SOURCES[@]}" \
    "$BUILD_DIR/obj/ioreport-$ARCH.o" \
    "$BUILD_DIR/obj/procs-$ARCH.o" \
    -o "$BUILD_DIR/obj/$APP_NAME-$ARCH"
  BINARIES+=("$BUILD_DIR/obj/$APP_NAME-$ARCH")
done

lipo -create -output "$APP/Contents/MacOS/$APP_NAME" "${BINARIES[@]}"
rm -rf "$BUILD_DIR/obj"

echo "==> 写入 Info.plist"
cp Info.plist "$APP/Contents/Info.plist"

if [ -f Resources/AppIcon.icns ]; then
  cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
  /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$APP/Contents/Info.plist" 2>/dev/null || true
fi

echo "==> 临时签名（ad-hoc）"
codesign --force --sign - --timestamp=none "$APP" >/dev/null 2>&1

echo "==> 完成：$APP  ($(du -sh "$APP" | cut -f1), $(lipo -archs "$APP/Contents/MacOS/$APP_NAME"))"
