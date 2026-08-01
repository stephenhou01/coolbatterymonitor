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

TEST_TMP_ROOT=${TMPDIR:-/tmp}
BUILD=$(mktemp -d "$TEST_TMP_ROOT/BatteryMonitor-l10n-build.XXXXXX")
TEST_HOME=$(mktemp -d "$TEST_TMP_ROOT/BatteryMonitor-l10n-home.XXXXXX")

# CFFIXED_USER_HOME 是 Foundation 测试使用的用户目录覆盖。测试进程因此只能看到
# 临时 Application Support 和 UserDefaults，绝不读写真实用户目录。
OVERRIDE="$TEST_HOME/Library/Application Support/BatteryMonitor/Languages"

# 所有删除目标都是本脚本创建、路径明确的单个文件或空目录。目录非空时 rmdir
# 会安全失败并留给系统临时目录清理；这里有意不使用任何递归删除。
cleanup() {
    rm -f "$OVERRIDE/de.json"
    rm -f "$OVERRIDE/it.json"
    rm -f "$TEST_HOME/Library/Preferences/com.stephen.L10nTest.plist"
    rm -f "$TEST_HOME/.CFUserTextEncoding"
    rm -f "$APP/Contents/Resources/Languages"
    rm -f "$APP/Contents/MacOS/T"
    rm -f "$APP/Contents/Info.plist"
    rm -f "$BUILD/main.swift"
    rmdir "$OVERRIDE" 2>/dev/null || true
    rmdir "$TEST_HOME/Library/Application Support/BatteryMonitor" 2>/dev/null || true
    rmdir "$TEST_HOME/Library/Application Support" 2>/dev/null || true
    rmdir "$TEST_HOME/Library/Preferences" 2>/dev/null || true
    rmdir "$TEST_HOME/Library/Caches" 2>/dev/null || true
    rmdir "$TEST_HOME/Library" 2>/dev/null || true
    rmdir "$TEST_HOME" 2>/dev/null || true
    rmdir "$APP/Contents/Resources" 2>/dev/null || true
    rmdir "$APP/Contents/MacOS" 2>/dev/null || true
    rmdir "$APP/Contents" 2>/dev/null || true
    rmdir "$APP" 2>/dev/null || true
    rmdir "$BUILD" 2>/dev/null || true
}
trap cleanup EXIT

APP="$BUILD/T.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
# 语言包是只读 fixture；使用符号链接避免复制整棵目录，也让清理保持逐文件。
ln -s "$ROOT/Localization/Languages" "$APP/Contents/Resources/Languages"
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

echo "▸ 阶段1：仅 bundle 内置语言包"
env HOME="$TEST_HOME" CFFIXED_USER_HOME="$TEST_HOME" "$APP/Contents/MacOS/T"

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
env HOME="$TEST_HOME" CFFIXED_USER_HOME="$TEST_HOME" PHASE=2 "$APP/Contents/MacOS/T"

echo
echo "✅ 全部通过"
