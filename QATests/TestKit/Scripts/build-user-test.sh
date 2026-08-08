#!/bin/bash
# Build or install the one fixed, signed BatteryMonitor UserTest App.
#
# Default: build Debug into a fixed DerivedData directory, replace the fixed
# UserTest App, sign and verify it, but do not launch it.
#
# Existing build: --source-app /absolute/path/BatteryMonitor.app
# Optional launch: --launch
# Readiness check (gracefully stops the fixed UserTest App if needed): --preflight
set -euo pipefail

cd "$(dirname "$0")/../../.."
ROOT=$(pwd)
QATEST_ROOT="$ROOT/QATests"
TESTKIT="$QATEST_ROOT/TestKit"
RUN_ROOT="$QATEST_ROOT/Run"
DERIVED_DATA="$RUN_ROOT/UserTestBuild/DerivedData"
TARGET_APP="$RUN_ROOT/UserTest/BatteryMonitor-UserTest.app"
TARGET_EXECUTABLE="$TARGET_APP/Contents/MacOS/BatteryMonitor"
ENTITLEMENTS="$ROOT/BatteryMonitor/BatteryMonitor.entitlements"
BUNDLE_ID="com.stephen.BatteryMonitor"
TEAM_ID=""
SIGN_IDENTITY=""

configuration="Debug"
source_app=""
should_launch=false
preflight_only=false

usage() {
    cat <<'USAGE'
Usage:
  ./QATests/TestKit/Scripts/build-user-test.sh [--configuration Debug|Release] [--launch]
  ./QATests/TestKit/Scripts/build-user-test.sh --source-app /absolute/path/BatteryMonitor.app [--launch]
  ./QATests/TestKit/Scripts/build-user-test.sh --preflight

Options:
  --configuration NAME  Build configuration when no --source-app is supplied.
  --source-app PATH     Install an already-built BatteryMonitor.app without rebuilding.
  --launch              Launch the fixed UserTest App after all checks pass.
  --no-launch           Do not launch (the default; useful for release verification).
  --preflight           Check prerequisites and gracefully stop the fixed UserTest App if running.
USAGE
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --configuration)
            test "$#" -ge 2 || { echo "--configuration 缺少参数" >&2; exit 2; }
            configuration=$2
            shift 2
            ;;
        --source-app)
            test "$#" -ge 2 || { echo "--source-app 缺少参数" >&2; exit 2; }
            source_app=$2
            shift 2
            ;;
        --launch)
            should_launch=true
            shift
            ;;
        --no-launch)
            should_launch=false
            shift
            ;;
        --preflight)
            preflight_only=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "未知参数：$1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

source "$TESTKIT/Scripts/load-qa-config.sh"
load_battery_monitor_qa_config
TEAM_ID="$QA_TEAM_ID"
SIGN_IDENTITY="$QA_SIGN_IDENTITY"

case "$configuration" in
    Debug|Release) ;;
    *)
        echo "不支持的构建类型：$configuration（仅支持 Debug / Release）" >&2
        exit 2
        ;;
esac

for tool in awk basename cat codesign date dirname ditto grep kill lipo mkdir mv open plutil ps security sleep spctl tr xcodebuild; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "缺少工具：$tool" >&2
        exit 1
    fi
done

running_pids() {
    ps -axo pid=,command= | awk -v expected="$TARGET_EXECUTABLE" '
        {
            pid = $1
            sub(/^[[:space:]]*[0-9]+[[:space:]]+/, "", $0)
            if ($0 == expected) print pid
        }
    '
}

stop_running_usertest() {
    local pids pid remaining

    pids=$(running_pids)
    if [ -z "$pids" ]; then
        return
    fi

    echo "▸ 正常退出固定 UserTest App（PID: $(echo "$pids" | tr '\n' ' ')）"
    while IFS= read -r pid; do
        [ -n "$pid" ] || continue
        kill -TERM "$pid" 2>/dev/null || true
    done <<<"$pids"

    for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
        remaining=$(running_pids)
        if [ -z "$remaining" ]; then
            echo "  固定 UserTest App 已退出"
            return
        fi
        sleep 0.25
    done

    echo "固定 UserTest App 收到正常退出信号后仍在运行（PID: $(echo "$remaining" | tr '\n' ' ')）。" >&2
    echo "为避免数据损坏，脚本不会强制结束；请人工退出后重试。" >&2
    exit 1
}

preflight() {
    local pids

    test -d "$QATEST_ROOT" || {
        echo "固定 QATests 目录不存在：$QATEST_ROOT" >&2
        exit 1
    }
    test -d "$TESTKIT" || {
        echo "TestKit 目录不存在：$TESTKIT" >&2
        exit 1
    }
    test -f "$ENTITLEMENTS" || {
        echo "Entitlements 文件不存在：$ENTITLEMENTS" >&2
        exit 1
    }
    if ! security find-identity -v -p codesigning | grep -Fq "\"$SIGN_IDENTITY\""; then
        echo "缺少固定开发签名：$SIGN_IDENTITY" >&2
        exit 1
    fi

    stop_running_usertest
    mkdir -p "$RUN_ROOT/UserTest"

    echo "  固定 UserTest 路径空闲，签名身份可用"
}

preflight
if [ "$preflight_only" = true ]; then
    exit 0
fi

marketing_version=$(awk -F '"' '/MARKETING_VERSION:/ {print $2; exit}' project.yml)
build_number=$(awk -F '"' '/CURRENT_PROJECT_VERSION:/ {print $2; exit}' project.yml)
test -n "$marketing_version"
test -n "$build_number"

if [ -z "$source_app" ]; then
    echo "▸ 编译 $configuration UserTest 源 App"
    mkdir -p "$DERIVED_DATA"
    settings=$(xcodebuild -project BatteryMonitor.xcodeproj -scheme BatteryMonitor \
        -configuration "$configuration" -destination 'generic/platform=macOS' \
        -derivedDataPath "$DERIVED_DATA" -showBuildSettings 2>/dev/null)
    built_products=$(awk -F ' = ' '/^[[:space:]]*BUILT_PRODUCTS_DIR = / {print $2; exit}' <<<"$settings")
    test -n "$built_products"

    xcodebuild -quiet -project BatteryMonitor.xcodeproj -scheme BatteryMonitor \
        -configuration "$configuration" -destination 'generic/platform=macOS' \
        -derivedDataPath "$DERIVED_DATA" CODE_SIGNING_ALLOWED=NO build
    source_app="$built_products/BatteryMonitor.app"
fi

if [[ "$source_app" != /* ]]; then
    source_app="$ROOT/$source_app"
fi
test -d "$source_app" || { echo "源 App 不存在：$source_app" >&2; exit 1; }
source_app=$(cd "$(dirname "$source_app")" && pwd)/$(basename "$source_app")
test "$source_app" != "$TARGET_APP" || {
    echo "--source-app 不能指向固定 UserTest App 自身" >&2
    exit 1
}

source_executable="$source_app/Contents/MacOS/BatteryMonitor"
source_plist="$source_app/Contents/Info.plist"
test -x "$source_executable" || { echo "源 App 缺少可执行文件：$source_executable" >&2; exit 1; }
test -f "$source_plist" || { echo "源 App 缺少 Info.plist：$source_plist" >&2; exit 1; }

source_bundle=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$source_plist")
source_marketing=$(plutil -extract CFBundleShortVersionString raw "$source_plist")
source_build=$(plutil -extract CFBundleVersion raw "$source_plist")
test "$source_bundle" = "$BUNDLE_ID" || { echo "源 App Bundle ID 不匹配：$source_bundle" >&2; exit 1; }
test "$source_marketing" = "$marketing_version" || { echo "源 App 版本不匹配：$source_marketing" >&2; exit 1; }
test "$source_build" = "$build_number" || { echo "源 App 构建号不匹配：$source_build" >&2; exit 1; }
source_archs=$(lipo -archs "$source_executable")

trash_root="$HOME/.Trash"
test -d "$trash_root" || { echo "废纸篓目录不存在：$trash_root" >&2; exit 1; }
replacement_stamp=$(date '+%Y%m%d-%H%M%S')
backup_app=""
replacement_complete=false

rollback_replacement() {
    local status=$?
    local failed_app

    if [ "$replacement_complete" = false ]; then
        set +e
        if [ -e "$TARGET_APP" ]; then
            failed_app="$trash_root/BatteryMonitor-UserTest-failed-${replacement_stamp}-$$.app"
            mv "$TARGET_APP" "$failed_app"
            echo "未完成的新 App 已移到废纸篓：$failed_app" >&2
        fi
        if [ -n "$backup_app" ] && [ -e "$backup_app" ] && [ ! -e "$TARGET_APP" ]; then
            mv "$backup_app" "$TARGET_APP"
            echo "已恢复替换前的固定 UserTest App。" >&2
        fi
        set -e
    fi
    return "$status"
}
trap rollback_replacement EXIT

echo "▸ 原位更新固定 UserTest App"
if [ -e "$TARGET_APP" ]; then
    backup_app="$trash_root/BatteryMonitor-UserTest-replaced-${replacement_stamp}-$$.app"
    test ! -e "$backup_app" || { echo "废纸篓备份目标已存在：$backup_app" >&2; exit 1; }
    mv "$TARGET_APP" "$backup_app"
fi
ditto "$source_app" "$TARGET_APP"

echo "▸ 使用固定开发身份签名"
codesign --force --deep --options runtime \
    --entitlements "$ENTITLEMENTS" \
    --sign "$SIGN_IDENTITY" --timestamp=none "$TARGET_APP"

echo "▸ 验证 Bundle、版本、架构和签名"
codesign --verify --deep --strict --verbose=2 "$TARGET_APP"
target_bundle=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$TARGET_APP/Contents/Info.plist")
target_marketing=$(plutil -extract CFBundleShortVersionString raw "$TARGET_APP/Contents/Info.plist")
target_build=$(plutil -extract CFBundleVersion raw "$TARGET_APP/Contents/Info.plist")
target_archs=$(lipo -archs "$TARGET_EXECUTABLE")
signature_info=$(codesign -dv --verbose=4 "$TARGET_APP" 2>&1)
actual_team=$(awk -F= '/^TeamIdentifier=/{print $2; exit}' <<<"$signature_info")
actual_authority=$(awk -F= '/^Authority=/{print $2; exit}' <<<"$signature_info")
test "$target_bundle" = "$BUNDLE_ID"
test "$target_marketing" = "$marketing_version"
test "$target_build" = "$build_number"
test "$target_archs" = "$source_archs"
test "$actual_team" = "$TEAM_ID"
test "$actual_authority" = "$SIGN_IDENTITY"
grep -E '^(Identifier|TeamIdentifier|CDHash)=' <<<"$signature_info"

echo "▸ 记录 Gatekeeper 评估"
assessment_status=0
assessment=$(spctl --assess --type execute --verbose=4 "$TARGET_APP" 2>&1) || assessment_status=$?
echo "$assessment"
if [ "$assessment_status" -ne 0 ]; then
    if ! grep -q 'rejected' <<<"$assessment"; then
        echo "spctl 返回了未经批准的异常结果；恢复旧 UserTest App。" >&2
        exit 1
    fi
    echo "  开发签名构建未公证；spctl rejected 已记录，不阻断固定 UserTest App。"
fi

replacement_complete=true
trap - EXIT

echo "  路径：$TARGET_APP"
echo "  构建：$configuration $target_marketing ($target_build)"
echo "  架构：$target_archs"
echo "  签名：$actual_authority / Team $actual_team"
if [ -n "$backup_app" ]; then
    echo "  旧 App 已移到废纸篓，可恢复：$backup_app"
fi

if [ "$should_launch" = true ]; then
    echo "▸ 启动固定 UserTest App"
    open -n "$TARGET_APP"
    launched_pids=""
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        launched_pids=$(running_pids)
        [ -n "$launched_pids" ] && break
        sleep 0.2
    done
    if [ -z "$launched_pids" ]; then
        echo "固定 App 已编译、签名并更新，但未检测到启动进程；运行验收可能受安全软件阻断。" >&2
        exit 1
    fi
    echo "  已启动固定 UserTest App（PID: $(echo "$launched_pids" | tr '\n' ' ')）"
else
    echo "  未启动 App（--no-launch）"
fi

echo "✅ 固定 BatteryMonitor UserTest App 已更新并验证"
