#!/bin/bash
# Verify that AppIcon PNGs contain real transparency, not merely an unused alpha channel.
set -euo pipefail
cd "$(dirname "$0")/.."

ROOT=$(pwd)
BUILD="$ROOT/.build/tests/icon-alpha"
BINARY="$BUILD/IconAlphaCheck"
# 默认 ad-hoc 签名，避免把作者个人开发证书变成测试前置条件。
SIGN_IDENTITY=${BATTERYMONITOR_TEST_SIGN_IDENTITY:--}
TARGET_TRIPLE="$(uname -m)-apple-macos14"

mkdir -p "$BUILD"
rm -f "$BINARY"

echo "▸ 编译 AppIcon 透明度检查（$TARGET_TRIPLE）"
swiftc -O -target "$TARGET_TRIPLE" \
    -framework CoreGraphics -framework ImageIO \
    -o "$BINARY" \
    "$ROOT/Tests/IconAlphaCheck.swift"

echo "▸ 签名 AppIcon 透明度检查"
codesign --force --sign "$SIGN_IDENTITY" --timestamp=none "$BINARY"
codesign --verify --strict "$BINARY"

echo "▸ 检查 AppIcon 透明像素"
"$BINARY" \
    "$ROOT/BatteryMonitor/Assets.xcassets/AppIcon.appiconset/icon_16.png" \
    "$ROOT/BatteryMonitor/Assets.xcassets/AppIcon.appiconset/icon_32.png" \
    "$ROOT/BatteryMonitor/Assets.xcassets/AppIcon.appiconset/icon_64.png" \
    "$ROOT/BatteryMonitor/Assets.xcassets/AppIcon.appiconset/icon_128.png" \
    "$ROOT/BatteryMonitor/Assets.xcassets/AppIcon.appiconset/icon_256.png" \
    "$ROOT/BatteryMonitor/Assets.xcassets/AppIcon.appiconset/icon_512.png" \
    "$ROOT/BatteryMonitor/Assets.xcassets/AppIcon.appiconset/icon_1024.png"
