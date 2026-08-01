#!/bin/bash
# InsightEngine / 年龄估算 / 硬件解析的边界测试。
#
#   ./Tests/run-insight-tests.sh
#
# 把 app 的真实源码（除 @main 入口，它与顶层测试代码冲突）编成一个可执行文件跑。
# 不依赖 Xcode、不依赖界面截图 —— 截图会被其他窗口抢焦点，不可重复。
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT=$(pwd)
BUILD="$ROOT/.build/tests/insight"
SIGN_IDENTITY=${BATTERYMONITOR_TEST_SIGN_IDENTITY:-Apple Development: ningjun hou (3FAB9WC88G)}
APP="$BUILD/InsightTests.app"
mkdir -p "$APP/Contents/MacOS"
rm -f "$APP/Contents/MacOS/InsightTests" "$APP/Contents/Info.plist"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>InsightTests</string>
<key>CFBundleIdentifier</key><string>com.stephen.BatteryMonitor.InsightTests</string>
<key>CFBundleName</key><string>BatteryMonitor Insight Tests</string>
<key>CFBundlePackageType</key><string>APPL</string>
</dict></plist>
PLIST

echo "▸ 编译…"
cp "$ROOT/Tests/InsightTests.swift" "$BUILD/main.swift"
# shellcheck disable=SC2046
swiftc -O -target arm64-apple-macos14 \
    -framework IOKit -framework AppKit -framework SwiftUI -framework Charts \
    -o "$APP/Contents/MacOS/InsightTests" \
    $(find "$ROOT/BatteryMonitor" -name "*.swift" ! -name "BatteryMonitorApp.swift") \
    "$BUILD/main.swift"

echo "▸ 签名"
codesign --force --sign "$SIGN_IDENTITY" --timestamp=none "$APP/Contents/MacOS/InsightTests"
codesign --force --deep --sign "$SIGN_IDENTITY" --timestamp=none "$APP"
codesign --verify --strict --deep "$APP"

echo "▸ 运行"
"$APP/Contents/MacOS/InsightTests"
