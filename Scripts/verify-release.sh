#!/bin/bash
# 发布前的本地、无上传验证。不会生成归档、修改版本号或访问 App Store Connect。
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT=$(pwd)
DERIVED_DATA="$ROOT/QATests/BuildValidation/ReleaseCheck/DerivedData"

# 用 grep -E 而不是 rg：ripgrep 不是这台机器上装着的东西，而以前预检要求它，导致整个
# 脚本从第一行就退出。交互 shell 里 `command -v rg` 看着有，那是 Claude Code 注入的
# shell 函数，bash 里并不存在。下面所有模式都是 POSIX ERE，grep 是系统自带的。
for tool in xcodebuild swiftc python3 plutil grep lipo sips; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "缺少工具：$tool" >&2
        exit 1
    fi
done

echo "▸ 检查测试脚本安全边界"
if grep -nE -- 'rm[[:space:]]+-[^[:space:]]*r|rm[[:space:]]+--recursive' QATests/run-fixed-qa.sh; then
    echo "测试脚本仍含递归删除命令" >&2
    exit 1
fi
if grep -nE -- '\$HOME/Library/Application Support/BatteryMonitor' QATests/run-fixed-qa.sh; then
    echo "测试脚本仍指向真实用户数据目录" >&2
    exit 1
fi

echo "▸ 检查发布配置"
grep -qE 'PRODUCT_BUNDLE_IDENTIFIER: com\.stephen\.BatteryMonitor' project.yml
grep -qE 'INFOPLIST_KEY_ITSAppUsesNonExemptEncryption: NO' project.yml
# README 必须声明双架构支持，与下面对实际二进制的 lipo 检查互为对照 —— 一处说支持
# Intel、另一处编出来只有 arm64，是会被用户当场发现的假宣传。
# 原断言找的是 `universal \`arm64\` + \`x86_64\` app`，那句话在 4e25f65（双语 README）
# 里被改写掉了，断言没跟着更新；又因为预检要求的 rg 不存在，脚本从第 9 行就退出，
# 这处失配一直没被跑到过。断言跟着 README 现在的措辞走，不是反过来改 README。
grep -qE 'Apple silicon and Intel Macs' README.md
marketing_version=$(awk -F '"' '/MARKETING_VERSION:/ {print $2; exit}' project.yml)
build_number=$(awk -F '"' '/CURRENT_PROJECT_VERSION:/ {print $2; exit}' project.yml)
test -n "$marketing_version"
test -n "$build_number"
test "$marketing_version" = "1.2.0"
# 构建号每次送审都要递增，写死它等于每次都得先改这个脚本；漏改一次，set -e 就让
# 后面所有关卡（图标、语言包、catalog、Release 编译）全部跑不到，而失败原因看起来
# 像是「验证脚本挂了」而不是「断言过期了」。这里只要求它非空且是纯数字，真正的
# 一致性由下面那条「app 的 CFBundleVersion 必须等于 project.yml」保证。
grep -qE '^[0-9]+$' <<<"$build_number"

echo "▸ 检查页面化本地化源"
python3 Localization/build-language-packs.py check

echo "▸ 检查 AppIcon 母版与完整尺寸集"
for size in 16 32 64 128 256 512 1024; do
    icon="BatteryMonitor/Assets.xcassets/AppIcon.appiconset/icon_${size}.png"
    test -f "$icon"
    width=$(sips -g pixelWidth "$icon" | awk '/pixelWidth:/ {print $2}')
    height=$(sips -g pixelHeight "$icon" | awk '/pixelHeight:/ {print $2}')
    alpha=$(sips -g hasAlpha "$icon" | awk '/hasAlpha:/ {print $2}')
    test "$width" = "$size"
    test "$height" = "$size"
    test "$alpha" = "yes"
done
./QATests/run-fixed-qa.sh icon

echo "▸ 检查 plist 与语言包"
plutil -lint ExportOptions.plist BatteryMonitor/BatteryMonitor.entitlements \
    BatteryMonitor/*.lproj/InfoPlist.strings >/dev/null
python3 - <<'PY'
import json
import re
from pathlib import Path

paths = sorted(Path("Localization/Languages").glob("*.json"))
assert len(paths) == 10, f"expected 10 language packs, got {len(paths)}"
reference_keys = None
required_help_keys = {
    "p.help_summary_soc", "p.help_summary_health", "p.help_summary_power",
    "p.help_summary_adapter_power", "p.help_source_adapter_power",
    "p.help_summary_adapter_output_power", "p.help_source_adapter_output_power",
    "p.help_summary_charging_power", "p.help_source_charging_power",
    "p.help_summary_cycle_count", "p.help_source_cycle_count",
    "p.help_summary_temperature", "p.help_summary_time_history",
    "p.help_summary_capacity", "p.help_origin_model",
    "p.help_origin_derived", "p.help_origin_iokit",
    "p.help_raw", "p.raw_explain_system_power", "p.raw_explain_system_load",
    "p.raw_explain_battery_voltage", "p.raw_explain_battery_current",
    "p.raw_explain_accumulated_load", "p.raw_explain_sample_count",
    "p.raw_explain_capacity", "p.raw_explain_time", "p.raw_explain_temperature",
    "p.raw_explain_cell", "p.raw_explain_resistance", "p.raw_explain_adapter",
    "p.raw_explain_cycle", "p.raw_explain_state", "p.raw_explain_reference",
    "p.raw_explain_derived", "p.raw_explain_generic",
}
required_raw_explanation_keys = {
    key for key in required_help_keys if key.startswith("p.raw_explain_")
}
required_menu_keys = {
    "p.menu_time", "p.menu_unplug", "p.menu_unplug_short",
    "p.menu_direct", "p.menu_forecast", "p.menu_waiting",
    "p.menu_open", "p.menu_settings", "p.menu_close",
    "p.menu_language", "p.menu_quit",
    "appearance.system", "appearance.light", "appearance.dark",
    "menu.config.title", "menu.config.second_metric", "menu.config.customize",
    "menu.config.show", "menu.config.hide", "menu.config.move_up",
    "menu.config.move_down", "menu.config.restore_defaults", "menu.config.empty",
    "menu.config.drag_to_reorder", "menu.config.add_more", "menu.config.manage_in_dashboard",
    "menu.metric.runtime", "menu.metric.power", "menu.metric.temperature",
    "menu.metric.health", "menu.metric.cycles", "menu.metric.current",
    "menu.process.none", "menu.process.latest_real_sample",
}
required_audit_keys = {
    "p.current_max_desc", "p.capacity_accessibility_four",
    "p.capacity_accessibility_gap", "p.duration_accessibility",
    "system.field.new.meaning", "system.field.new.recommendation",
    "system.field.new.note", "system.reliability.public",
    "system.reliability.legacy", "system.reliability.private",
    "system.group.temperature", "system.group.capacity", "system.group.power",
    "system.group.fault", "system.group.raw", "system.anomaly.permanent_failure",
    "system.anomaly.health_not_normal", "system.anomaly.thermal_critical",
    "system.anomaly.thermal_serious", "system.anomaly.battery_warning_final",
    "system.anomaly.battery_warning_early", "system.anomaly.cell_spread_warning",
    "system.anomaly.cell_spread_attention", "system.anomaly.temperature_high",
    "system.anomaly.temperature_low", "system.anomaly.diagnostic_nonzero",
}
pack_strings = {}
for path in paths:
    data = json.loads(path.read_text(encoding="utf-8"))
    assert data["_meta"]["code"] == path.stem, f"language code mismatch: {path}"
    assert isinstance(data.get("strings"), dict) and data["strings"], f"empty strings: {path}"
    keys = set(data["strings"])
    if reference_keys is None:
        reference_keys = keys
    assert keys == reference_keys, f"language key mismatch: {path}"
    assert required_help_keys <= keys, f"missing native help translations: {path}"
    assert required_menu_keys <= keys, f"missing native menu-bar translations: {path}"
    assert required_audit_keys <= keys, f"missing audit translations: {path}"
    pack_strings[path.stem] = data["strings"]

# Literal localization keys referenced by source code must exist in every pack.
swift_source = "\n".join(
    path.read_text(encoding="utf-8")
    for path in sorted(Path("BatteryMonitor").rglob("*.swift"))
)
literal_patterns = (
    r'\bL\(\s*"([^"]+)"',
    r'\bdashboardText\(\s*"([^"]+)"',
    r'\bhardwareText\(\s*"([^"]+)"',
    r'\btext\(\s*"((?:p|hw|shell|menu|system|appearance|insight|stat|rt|hist|proc|condition)\.[^"]+)"',
)
source_keys = set()
for pattern in literal_patterns:
    source_keys.update(re.findall(pattern, swift_source))
missing_source_keys = sorted(source_keys - reference_keys)
assert not missing_source_keys, f"source localization keys missing from packs: {missing_source_keys}"

# Format arguments are an ABI boundary: every translation must retain the English signature.
format_pattern = re.compile(
    r'%(?:\d+\$)?[-+ #0]*[\d.]*(?:hh|h|ll|l|L|z|j|t)?([diouxXeEfgGaAcspn@%])'
)
def format_signature(value):
    return [match for match in format_pattern.findall(value) if match != "%"]

english = pack_strings["en"]
for code, strings in sorted(pack_strings.items()):
    mismatches = [
        key for key, value in strings.items()
        if format_signature(value) != format_signature(english[key])
    ]
    assert not mismatches, f"format placeholder mismatch in {code}: {mismatches[:12]}"

# These newly exposed user-facing strings must be native rather than silent English fallback.
for code, strings in sorted(pack_strings.items()):
    if code == "en":
        continue
    untranslated = sorted(key for key in required_audit_keys if strings[key] == english[key])
    assert not untranslated, f"audit keys still use English fallback in {code}: {untranslated}"
    untranslated_raw = sorted(
        key for key in required_raw_explanation_keys if strings[key] == english[key]
    )
    assert not untranslated_raw, f"raw field explanations still use English fallback in {code}: {untranslated_raw}"

catalog = json.loads(Path("BatteryMonitor/Resources/SystemFieldCatalog.json").read_text(encoding="utf-8"))
assert catalog["schemaVersion"] == 1
assert catalog["fieldCount"] == len(catalog["fields"]) == 464
assert not any("sampleValue" in field or "本机实测值" in field for field in catalog["fields"])
sources = {}
for field in catalog["fields"]:
    sources[field["source"]] = sources.get(field["source"], 0) + 1
assert sources == {
    "IOPowerSources": 23,
    "AppleSmartBattery / IORegistry": 434,
    "IOPMCopyBatteryInfo": 2,
    "ProcessInfo": 5,
}

# The catalog's six display columns are localized through *Key lookups, so those keys
# are as much a release surface as the ones written literally in Swift.
catalog_key_fields = (
    "groupKey", "unitKey", "meaningKey", "reliabilityKey", "recommendationKey", "noteKey",
)
catalog_keys = {
    field[name]
    for field in catalog["fields"]
    for name in catalog_key_fields
    if field.get(name)
}
# 1. Every declared key must resolve to a non-empty, non-identity value in all ten packs.
for code, strings in sorted(pack_strings.items()):
    unresolved = sorted(
        key for key in catalog_keys
        if not strings.get(key) or strings[key] == key
    )
    assert not unresolved, f"catalog keys unresolved in {code}: {unresolved[:12]}"
# 2. Pin the count so a regenerated catalog cannot silently drop localization.
assert len(catalog_keys) == 147, f"expected 147 distinct catalog keys, got {len(catalog_keys)}"
# 3-4. Coupling guards.  The Chinese raw values are not dead weight: they are the
# zh-Hans copy *and* the tokens SystemFieldMetadata.isMeaningfulByDefault and
# SystemFieldValueConversion match against.  Stripping them in favour of keys alone
# leaves the table looking correct while the "useful by default" filter and the unit
# conversions silently stop matching, so assert a few known raw values survive.
catalog_units = {field["unit"] for field in catalog["fields"]}
missing_units = {"分钟", "秒", "原始温标"} - catalog_units
assert not missing_units, f"catalog lost raw unit values relied on for conversion: {missing_units}"
catalog_groups = {field["group"] for field in catalog["fields"]}
assert catalog_groups & {"标识", "身份"}, (
    "catalog lost the identifier group raw value that keeps serial numbers out of the default tab"
)
PY

echo "▸ 检查 Xcode 工程"
xcodebuild -project BatteryMonitor.xcodeproj -list -json | python3 -c '
import json, sys
p = json.load(sys.stdin)["project"]
assert "BatteryMonitor" in p["schemes"]
assert "BatteryMonitor" in p["targets"]
'
settings=$(xcodebuild -project BatteryMonitor.xcodeproj -scheme BatteryMonitor \
    -configuration Release -destination 'generic/platform=macOS' \
    -derivedDataPath "$DERIVED_DATA" -showBuildSettings 2>/dev/null)
grep -q 'PRODUCT_BUNDLE_IDENTIFIER = com.stephen.BatteryMonitor' <<<"$settings"
grep -q 'ARCHS = arm64 x86_64' <<<"$settings"
grep -q 'ENABLE_HARDENED_RUNTIME = YES' <<<"$settings"
if ! grep -q 'INFOPLIST_KEY_ITSAppUsesNonExemptEncryption = NO' <<<"$settings"; then
    echo "Xcode 工程尚未同步 project.yml；请先运行 xcodegen generate" >&2
    exit 1
fi

echo "▸ 编译 Release 应用（不签名、不归档、不上传）"
# 主 App 一旦成功编译，就必须能原位更新固定 UserTest App。先做只读预检，
# 避免 App 正在运行或签名身份缺失时先完成一份无法交付的 Release build。
./Scripts/build-user-test.sh --preflight
xcodebuild -quiet -project BatteryMonitor.xcodeproj -scheme BatteryMonitor \
    -configuration Release -destination 'generic/platform=macOS' \
    -derivedDataPath "$DERIVED_DATA" \
    CODE_SIGNING_ALLOWED=NO build
built_products=$(awk -F ' = ' '/^[[:space:]]*BUILT_PRODUCTS_DIR = / {print $2; exit}' <<<"$settings")
app="$built_products/BatteryMonitor.app"
test -x "$app/Contents/MacOS/BatteryMonitor"
test -f "$app/Contents/Resources/AppIcon.icns"
test "$(plutil -extract ITSAppUsesNonExemptEncryption raw "$app/Contents/Info.plist")" = "false"
test "$(plutil -extract CFBundleShortVersionString raw "$app/Contents/Info.plist")" = "$marketing_version"
test "$(plutil -extract CFBundleVersion raw "$app/Contents/Info.plist")" = "$build_number"
archs=$(lipo -archs "$app/Contents/MacOS/BatteryMonitor")
grep -qw arm64 <<<"$archs"
grep -qw x86_64 <<<"$archs"
APP_PATH="$app" python3 - <<'PY'
import os
from pathlib import Path

languages = Path(os.environ["APP_PATH"]) / "Contents/Resources/Languages"
packs = list(languages.glob("*.json"))
assert len(packs) == 10, f"built app expected 10 language packs, got {len(packs)}"
catalog = Path(os.environ["APP_PATH"]) / "Contents/Resources/SystemFieldCatalog.json"
assert catalog.is_file(), "built app missing SystemFieldCatalog.json"
PY

echo "▸ 更新固定 UserTest App（开发签名，不启动）"
./Scripts/build-user-test.sh --source-app "$app" --configuration Release --no-launch

echo "▸ 运行逻辑与本地化测试"
./QATests/run-fixed-qa.sh insight
./QATests/run-fixed-qa.sh l10n

echo
echo "✅ 发布前本地验证通过"
echo "提示：project.yml 是配置源；归档前仍需运行 xcodegen generate。"
