#!/bin/bash
# BatteryMonitor 唯一的本机运行型测试入口。
#
# 每个阶段依次关闭旧实例、覆盖同一个固定 App、重新签名和检查、执行测试，
# 并在阶段完成、失败、中断或脚本退出时关闭 QA Host：
#   QATests/Run/AutomationHost/BatteryMonitor-QAHost.app
#
# 用法：
#   ./QATests/TestKit/Scripts/run-test-app.sh all
#   ./QATests/TestKit/Scripts/run-test-app.sh icon
#   ./QATests/TestKit/Scripts/run-test-app.sh insight
#   ./QATests/TestKit/Scripts/run-test-app.sh l10n
set -euo pipefail

cd "$(dirname "$0")/../../.."
ROOT=$(pwd)
TESTKIT="$ROOT/QATests/TestKit"
BUILD="$ROOT/QATests/Run/AutomationHost"
APP="$BUILD/BatteryMonitor-QAHost.app"
EXECUTABLE="$APP/Contents/MacOS/BatteryMonitor-QAHost"
LOGS="$BUILD/Logs"
TEST_HOME="$BUILD/TestHome"
OVERRIDE="$TEST_HOME/Library/Application Support/BatteryMonitor/Languages"
ICON_MAIN="$TESTKIT/Sources/Icon/main.swift"
INSIGHT_MAIN="$TESTKIT/Sources/Insight/main.swift"
L10N_MAIN="$TESTKIT/Sources/Localization/main.swift"
BUNDLE_ID="com.stephen.BatteryMonitor.QAHost"
TEAM_ID=""
SIGN_IDENTITY=""
TARGET_TRIPLE="$(uname -m)-apple-macos14"
PHASE=${1:-all}

case "$PHASE" in
    all|icon|insight|l10n) ;;
    *)
        echo "未知测试阶段：$PHASE（可用：all / icon / insight / l10n）" >&2
        exit 2
        ;;
esac

for tool in swiftc codesign spctl plutil grep pgrep python3 tee awk find sleep unlink; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "缺少工具：$tool" >&2
        exit 1
    fi
done

source "$TESTKIT/Scripts/load-qa-config.sh"
load_battery_monitor_qa_config
TEAM_ID="$QA_TEAM_ID"
SIGN_IDENTITY="$QA_SIGN_IDENTITY"

remove_file_if_present() {
    local path=$1
    if [ -e "$path" ] || [ -L "$path" ]; then
        unlink "$path"
    fi
}

python3 Localization/build-language-packs.py check

mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/Languages" "$LOGS" "$OVERRIDE"

running_pids() {
    pgrep -f "^${EXECUTABLE}$" 2>/dev/null || true
}

stop_test_app() {
    local pids pid attempt
    pids=$(running_pids)
    if [ -z "$pids" ]; then
        return 0
    fi

    echo "▸ 关闭旧 BatteryMonitor QA Host"
    for pid in $pids; do
        kill "$pid" 2>/dev/null || true
    done

    for attempt in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
        if [ -z "$(running_pids)" ]; then
            return 0
        fi
        sleep 0.1
    done

    echo "固定 QA Host 未能正常退出；停止覆盖，避免替换正在运行的 App。" >&2
    exit 1
}

handle_test_interrupt() {
    local status=$1
    stop_test_app
    trap - EXIT INT TERM
    exit "$status"
}

trap stop_test_app EXIT
trap 'handle_test_interrupt 130' INT
trap 'handle_test_interrupt 143' TERM

write_info_plist() {
    local stage=$1
    cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>BatteryMonitor-QAHost</string>
<key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
<key>CFBundleName</key><string>BatteryMonitor QA Host</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>BatteryMonitorQAStage</key><string>${stage}</string>
</dict></plist>
PLIST
}

prepare_fixed_app() {
    local stage=$1
    stop_test_app
    remove_file_if_present "$EXECUTABLE"
    remove_file_if_present "$APP/Contents/Info.plist"
    write_info_plist "$stage"
}

sign_and_verify() {
    local actual_bundle actual_team actual_authority assessment signature_info

    echo "▸ 使用固定身份签名"
    codesign --force --options runtime --sign "$SIGN_IDENTITY" --timestamp=none "$EXECUTABLE"
    codesign --force --options runtime --sign "$SIGN_IDENTITY" --timestamp=none "$APP"

    echo "▸ 验证固定路径与签名身份"
    codesign --verify --deep --strict --verbose=2 "$APP"
    actual_bundle=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist")
    signature_info=$(codesign -dv --verbose=4 "$APP" 2>&1)
    actual_team=$(awk -F= '/^TeamIdentifier=/{print $2; exit}' <<<"$signature_info")
    actual_authority=$(awk -F= '/^Authority=/{print $2; exit}' <<<"$signature_info")
    test "$actual_bundle" = "$BUNDLE_ID"
    test "$actual_team" = "$TEAM_ID"
    test "$actual_authority" = "$SIGN_IDENTITY"
    grep -E '^(Identifier|TeamIdentifier|CDHash)=' <<<"$signature_info"

    echo "▸ 记录系统信任评估"
    if assessment=$(spctl --assess --type execute --verbose=4 "$APP" 2>&1); then
        echo "$assessment"
    else
        echo "$assessment"
        if ! grep -q 'rejected' <<<"$assessment"; then
            echo "spctl 返回了未经批准的异常结果；停止执行。" >&2
            exit 1
        fi
        echo "  固定 QA Host 使用开发签名且未公证；spctl rejected 为预期结果，不阻断本地调试。"
    fi
}

run_logged() {
    local name=$1
    shift
    local log="$LOGS/${name}.log"
    local status

    echo "▸ 运行 $name"
    set +e
    "$@" 2>&1 | tee "$log"
    status=${PIPESTATUS[0]}
    set -e
    if [ "$status" -ne 0 ]; then
        echo "$name 失败（exit $status），日志：$log" >&2
        return "$status"
    fi
    if [ -n "$(running_pids)" ]; then
        echo "$name 结束后测试 App 仍在运行；停止后续覆盖。" >&2
        return 1
    fi
    echo "  $name 通过，测试 App 已退出"
}

build_icon_phase() {
    prepare_fixed_app "icon"
    echo "▸ 编译 AppIcon 透明度测试（固定 QA Host）"
    swiftc -O -target "$TARGET_TRIPLE" \
        -framework CoreGraphics -framework ImageIO \
        -o "$EXECUTABLE" \
        "$ICON_MAIN"
    sign_and_verify
}

run_icon_phase() {
    build_icon_phase
    run_logged "icon" "$EXECUTABLE" \
        "$ROOT/BatteryMonitor/Assets.xcassets/AppIcon.appiconset/icon_16.png" \
        "$ROOT/BatteryMonitor/Assets.xcassets/AppIcon.appiconset/icon_32.png" \
        "$ROOT/BatteryMonitor/Assets.xcassets/AppIcon.appiconset/icon_64.png" \
        "$ROOT/BatteryMonitor/Assets.xcassets/AppIcon.appiconset/icon_128.png" \
        "$ROOT/BatteryMonitor/Assets.xcassets/AppIcon.appiconset/icon_256.png" \
        "$ROOT/BatteryMonitor/Assets.xcassets/AppIcon.appiconset/icon_512.png" \
        "$ROOT/BatteryMonitor/Assets.xcassets/AppIcon.appiconset/icon_1024.png"
}

build_insight_phase() {
    local swift_sources=()
    local swift_source

    prepare_fixed_app "insight"
    cp "$ROOT/Localization/Languages/"*.json "$APP/Contents/Resources/Languages/"
    cp "$ROOT/BatteryMonitor/Resources/SystemFieldCatalog.json" "$APP/Contents/Resources/"

    while IFS= read -r -d '' swift_source; do
        swift_sources+=("$swift_source")
    done < <(find "$ROOT/BatteryMonitor" -name "*.swift" ! -name "BatteryMonitorApp.swift" -print0)
    test "${#swift_sources[@]}" -gt 0

    echo "▸ 编译 Insight 测试（固定 QA Host）"
    swiftc -O -target "$TARGET_TRIPLE" \
        -framework IOKit -framework AppKit -framework SwiftUI -framework Charts \
        -o "$EXECUTABLE" \
        "${swift_sources[@]}" \
        "$INSIGHT_MAIN"
    sign_and_verify
}

run_insight_phase() {
    build_insight_phase
    run_logged "insight" "$EXECUTABLE"
}

build_l10n_phase() {
    prepare_fixed_app "l10n"
    cp "$ROOT/Localization/Languages/"*.json "$APP/Contents/Resources/Languages/"
    cp "$ROOT/BatteryMonitor/Resources/SystemFieldCatalog.json" "$APP/Contents/Resources/"

    echo "▸ 编译本地化测试（固定 QA Host）"
    swiftc -O -target "$TARGET_TRIPLE" \
        -o "$EXECUTABLE" \
        "$ROOT/BatteryMonitor/Services/Localization.swift" \
        "$L10N_MAIN"
    sign_and_verify
}

write_l10n_overrides() {
    python3 - "$ROOT/Localization/Languages" "$OVERRIDE" <<'PY'
import json, sys
src, dst = sys.argv[1], sys.argv[2]

def meta(code, name, order):
    return {"_meta": {"code": code, "name": name, "order": order}, "strings": {}}

d = meta("de", "Deutsch", 60)
d["strings"]["app.title"] = "ÜBERSCHRIEBEN-OK"
d["strings"]["stat.health"] = "HEALTH-OVERRIDE"
json.dump(d, open(f"{dst}/de.json", "w", encoding="utf-8"), ensure_ascii=False, indent=2)

d = meta("en", "English", 10)
d["strings"]["app.title"] = "EXTERNAL-EN-OK"
d["strings"]["status.charging"] = "BROKEN-EN %d W · %d W"
json.dump(d, open(f"{dst}/en.json", "w", encoding="utf-8"), ensure_ascii=False, indent=2)

d = meta("it", "Italiano", 90)
d["strings"]["status.charging"] = "ROTTO %d W · %d W"
d["strings"]["app.title"] = "IT-OVERRIDE-OK"
json.dump(d, open(f"{dst}/it.json", "w", encoding="utf-8"), ensure_ascii=False, indent=2)

d = json.load(open(f"{src}/pt.json", encoding="utf-8"))
d["strings"]["app.title"] = "OVERSIZED-PT-SHOULD-NOT-LOAD"
d["padding"] = "x" * (2 * 1024 * 1024)
json.dump(d, open(f"{dst}/pt.json", "w", encoding="utf-8"), ensure_ascii=False)
PY
}

run_l10n_phase() {
    remove_file_if_present "$OVERRIDE/de.json"
    remove_file_if_present "$OVERRIDE/en.json"
    remove_file_if_present "$OVERRIDE/it.json"
    remove_file_if_present "$OVERRIDE/pt.json"
    build_l10n_phase
    run_logged "l10n-phase1" env HOME="$TEST_HOME" CFFIXED_USER_HOME="$TEST_HOME" "$EXECUTABLE"

    echo "▸ 写入隔离的外部语言包 fixture"
    write_l10n_overrides
    run_logged "l10n-phase2" env HOME="$TEST_HOME" CFFIXED_USER_HOME="$TEST_HOME" PHASE=2 "$EXECUTABLE"
}

case "$PHASE" in
    icon) run_icon_phase ;;
    insight) run_insight_phase ;;
    l10n) run_l10n_phase ;;
    all)
        run_icon_phase
        run_insight_phase
        run_l10n_phase
        ;;
esac

stop_test_app
trap - EXIT INT TERM
echo
echo "✅ 固定 BatteryMonitor QA Host 测试通过（${PHASE}）；测试 App 已关闭"
