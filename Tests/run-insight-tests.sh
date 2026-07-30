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

BUILD=$(mktemp -d)
trap 'rm -rf "$BUILD"' EXIT

echo "▸ 编译…"
cp "$ROOT/Tests/InsightTests.swift" "$BUILD/main.swift"
# shellcheck disable=SC2046
swiftc -O -target arm64-apple-macos14 \
    -framework IOKit -framework AppKit -framework SwiftUI -framework Charts \
    -o "$BUILD/t" \
    $(find "$ROOT/BatteryMonitor" -name "*.swift" ! -name "BatteryMonitorApp.swift") \
    "$BUILD/main.swift"

echo "▸ 运行"
"$BUILD/t"
