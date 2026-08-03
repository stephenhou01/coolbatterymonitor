#!/bin/bash
# 语言包装载逻辑的确定性测试。不依赖 Xcode，也不依赖界面截图。
#
#   ./Tests/run-l10n-tests.sh
#
# 把真实的 Services/Localization.swift 编进一个临时 .app bundle（Bundle.main 才能
# 正确解析 Resources/Languages/），然后分两阶段跑：
#   阶段1 只有 bundle 内置包
#   阶段2 额外铺部分覆盖包、恶意英文基准、格式符非法包和超大包
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT=$(pwd)
BUILD="$ROOT/.build/tests/l10n"
TEST_HOME="$ROOT/.build/tests/l10n-home"
# 默认 ad-hoc 签名，避免测试绑定作者个人开发证书；可通过环境变量显式覆盖。
SIGN_IDENTITY=${BATTERYMONITOR_TEST_SIGN_IDENTITY:--}
TARGET_TRIPLE="$(uname -m)-apple-macos14"

# CFFIXED_USER_HOME 是 Foundation 测试使用的用户目录覆盖。测试进程因此只能看到
# 项目 .build 内隔离的 Application Support 和 UserDefaults，绝不读写真实用户目录。
OVERRIDE="$TEST_HOME/Library/Application Support/BatteryMonitor/Languages"

APP="$BUILD/T.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
# 固定构建目录只覆盖已知单文件，不做递归删除。
rm -f "$OVERRIDE/de.json" "$OVERRIDE/en.json" "$OVERRIDE/it.json" "$OVERRIDE/pt.json"
rm -f "$APP/Contents/MacOS/T" "$APP/Contents/Info.plist"
if [ -L "$APP/Contents/Resources/Languages" ]; then
    rm -f "$APP/Contents/Resources/Languages"
fi
# 语言包是只读 fixture。复制十个已知 JSON 到包内，让固定路径下的测试 App
# 可以正常签名，不依赖指向包外的符号链接。
mkdir -p "$APP/Contents/Resources/Languages"
cp "$ROOT/Localization/Languages/"*.json "$APP/Contents/Resources/Languages/"
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

echo "▸ 编译（${TARGET_TRIPLE}）…"
# swiftc 要求含顶层语句的文件必须叫 main.swift，所以拷一份过去再编
cp "$ROOT/Tests/L10nTests.swift" "$BUILD/main.swift"
swiftc -O -target "$TARGET_TRIPLE" \
    -o "$APP/Contents/MacOS/T" \
    "$ROOT/BatteryMonitor/Services/Localization.swift" \
    "$BUILD/main.swift"

echo "▸ 签名"
codesign --force --sign "$SIGN_IDENTITY" --timestamp=none "$APP/Contents/MacOS/T"
codesign --force --deep --sign "$SIGN_IDENTITY" --timestamp=none "$APP"
codesign --verify --strict --deep "$APP"

echo "▸ 阶段1：仅 bundle 内置语言包"
env HOME="$TEST_HOME" CFFIXED_USER_HOME="$TEST_HOME" "$APP/Contents/MacOS/T"

echo
echo "▸ 阶段2：部分覆盖 + 恶意英文基准 + 坏格式符 + 超大包"
mkdir -p "$OVERRIDE"
python3 - "$ROOT/Localization/Languages" "$OVERRIDE" <<'PY'
import json, sys
src, dst = sys.argv[1], sys.argv[2]

def meta(code, name, order):
    return {"_meta": {"code": code, "name": name, "order": order}, "strings": {}}

# 部分覆盖包：只提供两个 key。第三个 stat.cycles 必须保留内置德语；若实现是
# 整包替换，它会错误回落英文，L10nTests.swift 会直接失败。
d = meta("de", "Deutsch", 60)
d["strings"]["app.title"] = "ÜBERSCHRIEBEN-OK"
d["strings"]["stat.health"] = "HEALTH-OVERRIDE"
json.dump(d, open(f"{dst}/de.json", "w", encoding="utf-8"), ensure_ascii=False, indent=2)

# 外部 en.json 不能成为格式符校验基准。这个恶意 key 把 Double 改成 Int；正确实现
# 会丢弃它、继续以 bundle 内英文为可信基准。安全的 app.title 仍允许按 key 覆盖。
d = meta("en", "English", 10)
d["strings"]["app.title"] = "EXTERNAL-EN-OK"
d["strings"]["status.charging"] = "BROKEN-EN %d W · %d W"
json.dump(d, open(f"{dst}/en.json", "w", encoding="utf-8"), ensure_ascii=False, indent=2)

# 坏包：status.charging 的参数类型签名从 [Double, Int] 篡改成 [Int, Int]，应被
# 丢弃并回落可信 bundle 英文；同包另一个合法 key 应保留。
d = meta("it", "Italiano", 90)
d["strings"]["status.charging"] = "ROTTO %d W · %d W"
d["strings"]["app.title"] = "IT-OVERRIDE-OK"
json.dump(d, open(f"{dst}/it.json", "w", encoding="utf-8"), ensure_ascii=False, indent=2)

# 超大包：即使结构合法也不能被加载，防止外部语言包无限占用内存。
d = json.load(open(f"{src}/pt.json", encoding="utf-8"))
d["strings"]["app.title"] = "OVERSIZED-PT-SHOULD-NOT-LOAD"
d["padding"] = "x" * (2 * 1024 * 1024)
json.dump(d, open(f"{dst}/pt.json", "w", encoding="utf-8"), ensure_ascii=False)
PY
env HOME="$TEST_HOME" CFFIXED_USER_HOME="$TEST_HOME" PHASE=2 "$APP/Contents/MacOS/T"

echo
echo "✅ 全部通过"
