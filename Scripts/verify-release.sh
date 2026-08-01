#!/bin/bash
# 发布前的本地、无上传验证。不会生成归档、修改版本号或访问 App Store Connect。
set -euo pipefail

cd "$(dirname "$0")/.."

for tool in xcodebuild swiftc python3 plutil rg lipo; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "缺少工具：$tool" >&2
        exit 1
    fi
done

echo "▸ 检查测试脚本安全边界"
if rg -n -- 'rm[[:space:]]+-[^[:space:]]*r|rm[[:space:]]+--recursive' Tests/run-*.sh; then
    echo "测试脚本仍含递归删除命令" >&2
    exit 1
fi
if rg -n -- '\$HOME/Library/Application Support/BatteryMonitor' Tests/run-*.sh; then
    echo "测试脚本仍指向真实用户数据目录" >&2
    exit 1
fi

echo "▸ 检查发布配置"
rg -q 'PRODUCT_BUNDLE_IDENTIFIER: com\.stephen\.BatteryMonitor' project.yml
rg -q 'INFOPLIST_KEY_ITSAppUsesNonExemptEncryption: NO' project.yml
rg -q 'universal `arm64` \+ `x86_64` app' README.md
marketing_version=$(awk -F '"' '/MARKETING_VERSION:/ {print $2; exit}' project.yml)
build_number=$(awk -F '"' '/CURRENT_PROJECT_VERSION:/ {print $2; exit}' project.yml)
test -n "$marketing_version"
test -n "$build_number"

echo "▸ 检查 plist 与语言包"
plutil -lint ExportOptions.plist BatteryMonitor/BatteryMonitor.entitlements \
    BatteryMonitor/*.lproj/InfoPlist.strings >/dev/null
python3 - <<'PY'
import json
from pathlib import Path

paths = sorted(Path("Localization/Languages").glob("*.json"))
assert len(paths) == 10, f"expected 10 language packs, got {len(paths)}"
reference_keys = None
required_help_keys = {
    "p.help_summary_soc", "p.help_summary_health", "p.help_summary_power",
    "p.help_summary_temperature", "p.help_summary_time_history",
    "p.help_summary_capacity", "p.help_origin_model",
    "p.help_origin_derived", "p.help_origin_iokit",
}
required_menu_keys = {
    "p.menu_time", "p.menu_unplug", "p.menu_unplug_short",
    "p.menu_direct", "p.menu_forecast", "p.menu_waiting",
    "p.menu_open", "p.menu_settings", "p.menu_close",
    "p.menu_language", "p.menu_quit",
}
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
PY

echo "▸ 检查 Xcode 工程"
xcodebuild -project BatteryMonitor.xcodeproj -list -json | python3 -c '
import json, sys
p = json.load(sys.stdin)["project"]
assert "BatteryMonitor" in p["schemes"]
assert "BatteryMonitor" in p["targets"]
'
settings=$(xcodebuild -project BatteryMonitor.xcodeproj -scheme BatteryMonitor \
    -configuration Release -destination 'generic/platform=macOS' -showBuildSettings 2>/dev/null)
grep -q 'PRODUCT_BUNDLE_IDENTIFIER = com.stephen.BatteryMonitor' <<<"$settings"
grep -q 'ARCHS = arm64 x86_64' <<<"$settings"
grep -q 'ENABLE_HARDENED_RUNTIME = YES' <<<"$settings"
if ! grep -q 'INFOPLIST_KEY_ITSAppUsesNonExemptEncryption = NO' <<<"$settings"; then
    echo "Xcode 工程尚未同步 project.yml；请先运行 xcodegen generate" >&2
    exit 1
fi

echo "▸ 编译 Release 应用（不签名、不归档、不上传）"
xcodebuild -quiet -project BatteryMonitor.xcodeproj -scheme BatteryMonitor \
    -configuration Release -destination 'generic/platform=macOS' \
    CODE_SIGNING_ALLOWED=NO build
built_products=$(awk -F ' = ' '/^[[:space:]]*BUILT_PRODUCTS_DIR = / {print $2; exit}' <<<"$settings")
app="$built_products/BatteryMonitor.app"
test -x "$app/Contents/MacOS/BatteryMonitor"
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

echo "▸ 运行逻辑与本地化测试"
./Tests/run-insight-tests.sh
./Tests/run-l10n-tests.sh

echo
echo "✅ 发布前本地验证通过"
echo "提示：project.yml 是配置源；归档前仍需运行 xcodegen generate。"
