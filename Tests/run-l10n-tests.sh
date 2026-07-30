#!/bin/bash
# 语言包装载逻辑的确定性测试。不依赖 Xcode，也不依赖界面截图。
#
#   ./Tests/run-l10n-tests.sh
#
# 把真实的 Services/Localization.swift 编进一个临时 .app bundle（Bundle.main 才能
# 正确解析 Resources/Languages/），然后分两阶段跑：
#   阶段1 只有 bundle 内置包
#   阶段2 额外铺一个覆盖包和一个格式符签名非法的坏包
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT=$(pwd)

# 测试进程未沙盒化，所以覆盖目录是 ~/Library/Application Support/（沙盒下的 app
# 走的是自己容器内的同名路径）。
OVERRIDE="$HOME/Library/Application Support/BatteryMonitor/Languages"
BUILD=$(mktemp -d)
trap 'rm -rf "$BUILD"; rm -rf "$OVERRIDE"' EXIT

APP="$BUILD/T.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp -R "$ROOT/Localization/Languages" "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>T</string>
<key>CFBundleIdentifier</key><string>com.stephen.L10nTest</string>
<key>CFBundleName</key><string>T</string>
<key>CFBundlePackageType</key><string>APPL</string>
</dict></plist>
PLIST

echo "▸ 编译…"
# swiftc 要求含顶层语句的文件必须叫 main.swift，所以拷一份过去再编
cp "$ROOT/Tests/L10nTests.swift" "$BUILD/main.swift"
swiftc -O -target arm64-apple-macos14 \
    -o "$APP/Contents/MacOS/T" \
    "$ROOT/BatteryMonitor/Services/Localization.swift" \
    "$BUILD/main.swift"

rm -rf "$OVERRIDE"      # 确保阶段1 不受残留覆盖包干扰

echo "▸ 阶段1：仅 bundle 内置语言包"
"$APP/Contents/MacOS/T"

echo
echo "▸ 阶段2：额外铺覆盖包 + 格式符非法的坏包"
mkdir -p "$OVERRIDE"
python3 - "$ROOT/Localization/Languages" "$OVERRIDE" <<'PY'
import json, sys
src, dst = sys.argv[1], sys.argv[2]
# 覆盖包：改两个 key，第三个不动（验证是按 key 合并还是整包替换）
d = json.load(open(f"{src}/de.json", encoding="utf-8"))
d["strings"]["app.title"] = "ÜBERSCHRIEBEN-OK"
d["strings"]["stat.health"] = "HEALTH-OVERRIDE"
json.dump(d, open(f"{dst}/de.json", "w", encoding="utf-8"), ensure_ascii=False, indent=2)
# 坏包：status.charging 的签名从 [f,d] 篡改成 [d,d]，应被丢弃并回落 en；
# 同包里另一个合法 key 应保留（验证是按 key 丢弃而不是整包拒绝）
d = json.load(open(f"{src}/it.json", encoding="utf-8"))
d["strings"]["status.charging"] = "ROTTO %d W · %d W"
d["strings"]["app.title"] = "IT-OVERRIDE-OK"
json.dump(d, open(f"{dst}/it.json", "w", encoding="utf-8"), ensure_ascii=False, indent=2)
PY
PHASE=2 "$APP/Contents/MacOS/T"

echo
echo "✅ 全部通过"
