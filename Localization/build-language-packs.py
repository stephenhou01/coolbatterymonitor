#!/usr/bin/env python3
"""Build and query BatteryMonitor localization packs from page-owned sources.

`Localization/Sources/**/*.json` is the editing authority.  The ten runtime
packs under `Localization/Languages/` are generated projections grouped by
language because that is the shape the app loader consumes.

Commands:
  bootstrap  One-time migration from the existing ten runtime packs.
  check      Validate sources and prove runtime packs match them (default).
  write      Regenerate all runtime packs without changing key names.
  list       Show page/section counts.
  find       Locate keys by key substring and report source ownership/usages.
"""

from __future__ import annotations

import argparse
import ast
from collections import Counter, defaultdict
import json
from pathlib import Path
import re
import sys
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
SOURCE_ROOT = ROOT / "Localization" / "Sources"
MANIFEST_PATH = SOURCE_ROOT / "manifest.json"
LANGUAGE_ROOT = ROOT / "Localization" / "Languages"

FORMAT_PATTERN = re.compile(
    r"%(?:(\d+)\$)?[-+ #0']*[\d.]*(hh|h|ll|l|L|z|j|t)?([diouxXeEfgGaAcspn@%])"
)
BRACE_PATTERN = re.compile(r"\{([A-Za-z_][A-Za-z0-9_]*)\}")


SCOPE_SPECS: dict[str, dict[str, Any]] = {
    "app-shell/navigation": {
        "title": "App 外壳 / 导航",
        "description": "侧边栏、页面入口、页面副标题和窗口级导航文案。",
        "consumers": ["ContentView", "DashboardShellView"],
    },
    "overview/battery-status": {
        "title": "总览 / 电池状态",
        "description": "电量、充放电状态、温度、循环、健康和状态提示。",
        "consumers": ["DashboardOverviewPage"],
    },
    "overview/power-flow": {
        "title": "总览 / 能量流向",
        "description": "适配器、电池、整机三个节点及能量流向说明。",
        "consumers": ["DashboardOverviewPage", "PowerFlowDiagram"],
    },
    "overview/runtime-comparison": {
        "title": "总览 / 续航时间对照",
        "description": "系统、稳健和当前负载三套剩余时间口径。",
        "consumers": ["DashboardOverviewPage"],
    },
    "technical/remaining-time": {
        "title": "技术参数 / 剩余时间主卡",
        "description": "剩余时间主卡及三套预测口径的说明。",
        "consumers": ["RemainingTimeHeroSection"],
    },
    "technical/runtime-benchmark": {
        "title": "技术参数 / 官方续航对比",
        "description": "机型基准、测试条件和续航审计文案。",
        "consumers": ["RuntimeBenchmarkSection"],
    },
    "technical/runtime-history": {
        "title": "技术参数 / 续航历史",
        "description": "拔电历史、学习进度、趋势和时间范围。",
        "consumers": ["RemainingTimeHistorySection"],
    },
    "technical/power-center": {
        "title": "技术参数 / 功率中心",
        "description": "功率图、实时刷新、统计窗口和活跃进程。",
        "consumers": ["PowerCenterSection"],
    },
    "technical/capacity-breakdown": {
        "title": "技术参数 / 容量拆解",
        "description": "设计容量、当前上限、不可用容量和永久损耗。",
        "consumers": ["CapacityBreakdownSection"],
    },
    "technical/metric-reference": {
        "title": "技术参数 / 指标与参考区间",
        "description": "温度、功率、健康、循环、电芯和阻抗参考区间。",
        "consumers": ["MetricReferenceSection"],
    },
    "technical/consumer-explanation": {
        "title": "技术参数 / 消费者解释",
        "description": "指标关系、老化判断和面向消费者的解释。",
        "consumers": ["ConsumerExplanationSection"],
    },
    "technical/hardware-details": {
        "title": "技术参数 / 完整硬件字段",
        "description": "硬件字段名称、含义、范围、用途和分组。",
        "consumers": ["CompleteHardwareDetailView", "CompleteHardwareMetricCatalog"],
    },
    "technical/system-workbench": {
        "title": "技术参数 / 系统数据工作台",
        "description": "系统字段搜索、筛选、来源和可靠性文案。",
        "consumers": ["SystemDataWorkbenchView"],
    },
    "trends/realtime-monitor": {
        "title": "趋势 / 实时监控",
        "description": "实时曲线、时间窗、拟合点和指标摘要。",
        "consumers": ["DashboardTrendsPage", "RealtimeMonitorView"],
    },
    "trends/process-list": {
        "title": "趋势 / 进程列表",
        "description": "进程 CPU 上下文、刷新状态和负载等级。",
        "consumers": ["ProcessListView"],
    },
    "trends/charging-history": {
        "title": "趋势 / 充放电历史",
        "description": "充放电会话、速率、时长和空状态。",
        "consumers": ["HistoryChartView"],
    },
    "diagnostics/insights": {
        "title": "诊断 / 洞察卡片",
        "description": "健康、充电习惯、配件和功耗诊断。",
        "consumers": ["DashboardDiagnosticsPage", "InsightCards"],
    },
    "diagnostics/system-anomalies": {
        "title": "诊断 / 系统异常",
        "description": "系统异常名称和诊断结果。",
        "consumers": ["DashboardDiagnosticsPage", "SystemDataCollector"],
    },
    "settings/preferences": {
        "title": "设置",
        "description": "外观、语言、实时刷新、隐私和菜单栏入口。",
        "consumers": ["DashboardSettingsPage"],
    },
    "menubar/dashboard": {
        "title": "菜单栏",
        "description": "状态项、弹出面板、指标配置、趋势和进程。",
        "consumers": ["MenuBarStatusItem", "MenuBarDashboardView"],
    },
    "shared/core": {
        "title": "跨页面 / 通用",
        "description": "跨页面复用的 App 名称、状态、动作和辅助功能文案。",
        "consumers": ["multiple"],
    },
    "shared/help": {
        "title": "跨页面 / 指标帮助框架",
        "description": "问号面板公共结构、原始字段说明、读取时间和数据来源。",
        "consumers": ["DashboardHelp", "MetricHelpView"],
    },
    "catalogs/system-fields": {
        "title": "数据目录 / 系统字段",
        "description": "SystemFieldCatalog 的分组、单位、含义、可靠性、建议和备注。",
        "consumers": ["SystemFieldCatalog.json", "SystemDataWorkbenchView"],
    },
}


def read_json(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise ValueError(f"无法读取 JSON：{path}: {error}") from error
    if not isinstance(value, dict):
        raise ValueError(f"JSON 顶层必须是 object：{path}")
    return value


def write_json(path: Path, value: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(value, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )


def starts(value: str, prefixes: tuple[str, ...]) -> bool:
    return any(value.startswith(prefix) for prefix in prefixes)


def classify_key(key: str) -> str:
    """Return semantic ownership for the one-time migration.

    This intentionally classifies by the product concept that owns the copy,
    not by every place that happens to render it.  Runtime usages are queried
    separately by `find` and do not move ownership into a generic bucket.
    """
    if key.startswith("system.catalog."):
        return "catalogs/system-fields"
    if key.startswith("system.anomaly."):
        return "diagnostics/system-anomalies"
    if key.startswith("system."):
        return "technical/system-workbench"
    if key.startswith("insight."):
        return "diagnostics/insights"
    if key.startswith("hw."):
        return "technical/hardware-details"
    if key.startswith("menu.") or key.startswith("p.menu_"):
        return "menubar/dashboard"
    if key.startswith("appearance."):
        return "settings/preferences"
    if key.startswith("rt."):
        return "trends/realtime-monitor"
    if key.startswith(("proc.", "usage.")):
        return "trends/process-list"
    if key.startswith("hist."):
        return "trends/charging-history"
    if key.startswith(("status.", "gauge.", "stat.", "condition.", "tip.")):
        return "overview/battery-status"
    if key.startswith(("app.", "lang.")) or key == "calculating":
        return "shared/core"

    if key.startswith("shell."):
        name = key.removeprefix("shell.")
        navigation = {
            "overview", "technical", "trends", "diagnostics", "settings",
            "sidebar_subtitle", "local_only", "technical_subtitle",
            "trends_subtitle", "diagnostics_subtitle", "settings_subtitle",
        }
        settings = {
            "appearance", "live_refresh", "privacy_note", "dynamic_trends",
            "last_minutes", "instant_power", "current", "top_processes", "cpu_context",
        }
        if name in navigation:
            return "app-shell/navigation"
        if name in settings:
            return "settings/preferences"
        if starts(name, (
            "runtime", "instant_runtime", "apple_runtime", "stable_runtime",
            "current_runtime", "derived_runtime", "system_runtime",
        )):
            return "overview/runtime-comparison"
        if starts(name, ("flow_", "state_")) or name in {
            "battery_current", "time_to_full", "adapter_output_power", "whole_mac_input",
        }:
            return "overview/power-flow"
        if name in {"diagnosing", "system_anomalies"}:
            return "diagnostics/system-anomalies"
        return "overview/battery-status"

    if key.startswith("p."):
        name = key.removeprefix("p.")
        if starts(name, ("system_data", "system_tab", "system_no", "system_others_")):
            return "technical/system-workbench"
        if starts(name, (
            "trend_", "help_summary_health", "help_summary_power",
            "help_summary_adapter", "help_summary_charging", "help_summary_cycle_count",
        )):
            return "trends/realtime-monitor"
        if starts(name, (
            "raw_", "field_", "help_", "system_source_", "adapter_",
        )):
            return "shared/help"
        if starts(name, ("hw_", "hw.")):
            return "technical/hardware-details"
        if starts(name, (
            "power_center", "live_", "pause_", "resume_", "refresh_", "window_",
            "active_process", "no_active_process", "process_", "power_axis",
            "power_hover", "power_collecting", "current_power_short",
        )):
            return "technical/power-center"
        if starts(name, (
            "runtime_compare", "runtime_system", "runtime_stable", "runtime_current",
            "runtime_raw_unavailable", "runtime_unavailable",
        )):
            return "technical/remaining-time"
        if starts(name, (
            "unplug_", "remaining_trend", "no_estimate", "direct_source",
            "sample_cadence", "no_recalc", "no_history", "learn_", "unlock_",
            "ul_", "chart_",
        )):
            return "technical/runtime-history"
        if starts(name, (
            "audit_", "runtime_audit", "baseline_compare", "model_design_energy",
            "current_full_energy", "energy_in_battery", "current_use_estimate", "full_tank",
        )):
            return "technical/runtime-benchmark"
        if starts(name, (
            "capacity", "seg_", "card_", "design_capacity", "current_max",
            "current_actual", "used_", "permanent_", "derive_gap", "derive_four",
            "loss_split", "use_loss", "unusable",
        )):
            return "technical/capacity-breakdown"
        if starts(name, (
            "spec_", "good_range", "history_", "cumulative_", "low_effect",
            "high_effect", "health_low", "health_high", "cycle_low", "cycle_high",
            "temp_low", "temp_high", "power_low", "power_high", "src_",
            "no_fixed_range", "id_no_range", "counter_range", "rated_value",
            "cb_", "ra_", "cy_", "hp_", "pw_", "pv_", "t_", "tb_", "p_",
            "scen_", "range", "left_axis", "right_axis",
        )):
            return "technical/metric-reference"
        if starts(name, (
            "why_", "aha_", "health_two", "aging_", "time_jump", "priority_",
            "tagline", "forecast_", "snapshot", "usage_basis", "system_charge",
            "geek", "footer", "hover_hint", "nonlinear", "collecting", "remaining",
            "where_", "eq_", "dual_", "split_", "read_title", "derive", "cadence",
            "current_power",
        )):
            return "technical/consumer-explanation"

    return "shared/core"


def load_runtime_packs() -> tuple[list[dict[str, Any]], dict[str, dict[str, str]]]:
    paths = sorted(LANGUAGE_ROOT.glob("*.json"))
    if not paths:
        raise ValueError(f"没有运行时语言包：{LANGUAGE_ROOT}")
    metas: list[dict[str, Any]] = []
    packs: dict[str, dict[str, str]] = {}
    reference_keys: set[str] | None = None
    for path in paths:
        payload = read_json(path)
        meta = payload.get("_meta")
        strings = payload.get("strings")
        if not isinstance(meta, dict) or not isinstance(strings, dict):
            raise ValueError(f"语言包结构无效：{path}")
        code = meta.get("code")
        if code != path.stem:
            raise ValueError(f"语言代码与文件名不一致：{path}")
        if not all(isinstance(key, str) and isinstance(value, str) for key, value in strings.items()):
            raise ValueError(f"语言包 strings 必须是字符串映射：{path}")
        keys = set(strings)
        if reference_keys is None:
            reference_keys = keys
        elif keys != reference_keys:
            raise ValueError(f"语言包 key 集合不一致：{path}")
        metas.append(dict(meta))
        packs[code] = dict(strings)
    metas.sort(key=lambda item: (item.get("order", 999), item["code"]))
    return metas, packs


def bootstrap() -> None:
    existing_sources = [
        path for path in SOURCE_ROOT.rglob("*.json")
        if path != MANIFEST_PATH
    ] if SOURCE_ROOT.exists() else []
    if MANIFEST_PATH.exists() or existing_sources:
        raise ValueError("Sources 已存在；bootstrap 只允许在首次迁移时运行")

    metas, packs = load_runtime_packs()
    codes = [meta["code"] for meta in metas]
    english = packs.get("en")
    if english is None:
        raise ValueError("bootstrap 需要 en.json 作为 key 顺序与格式基准")

    manifest = {
        "schemaVersion": 1,
        "description": "页面/区块源文件是唯一编辑权威；Languages 是生成产物。",
        "languages": metas,
        "scopeOrder": list(SCOPE_SPECS),
    }
    write_json(MANIFEST_PATH, manifest)

    buckets: dict[str, dict[str, dict[str, str]]] = defaultdict(dict)
    for key in english:
        scope = classify_key(key)
        if scope not in SCOPE_SPECS:
            raise ValueError(f"未知 scope：{scope} ({key})")
        buckets[scope][key] = {code: packs[code][key] for code in codes}

    for scope, spec in SCOPE_SPECS.items():
        payload = {
            "_meta": {"scope": scope, **spec},
            "strings": buckets.get(scope, {}),
        }
        write_json(SOURCE_ROOT / f"{scope}.json", payload)

    print(f"已迁移 {len(english)} 个 key → {len(SCOPE_SPECS)} 个页面/区块源文件")
    for scope in SCOPE_SPECS:
        print(f"{len(buckets.get(scope, {})):4}  {scope}")


def load_manifest() -> tuple[dict[str, Any], list[str]]:
    manifest = read_json(MANIFEST_PATH)
    if manifest.get("schemaVersion") != 1:
        raise ValueError("Sources/manifest.json schemaVersion 必须为 1")
    languages = manifest.get("languages")
    if not isinstance(languages, list) or not languages:
        raise ValueError("manifest languages 不能为空")
    codes: list[str] = []
    for meta in languages:
        if not isinstance(meta, dict) or not isinstance(meta.get("code"), str):
            raise ValueError("manifest language meta 无效")
        codes.append(meta["code"])
    if len(codes) != len(set(codes)):
        raise ValueError("manifest 存在重复语言代码")
    if "en" not in codes:
        raise ValueError("manifest 必须包含 en")
    return manifest, codes


def format_signature(value: str) -> list[str]:
    signature: list[str] = []
    for position, length, conversion in FORMAT_PATTERN.findall(value):
        if conversion == "%":
            continue
        signature.append(f"{position + '$' if position else ''}{length}{conversion}")
    return signature


def load_sources() -> tuple[dict[str, Any], list[str], dict[str, dict[str, str]], dict[str, str]]:
    manifest, codes = load_manifest()
    translations: dict[str, dict[str, str]] = {}
    ownership: dict[str, str] = {}
    discovered_paths = sorted(
        path for path in SOURCE_ROOT.rglob("*.json")
        if path != MANIFEST_PATH
    )
    if not discovered_paths:
        raise ValueError("Sources 下没有页面/区块源文件")

    scope_order = manifest.get("scopeOrder")
    if not isinstance(scope_order, list) or not all(isinstance(scope, str) for scope in scope_order):
        raise ValueError("manifest scopeOrder 必须是字符串数组")
    if len(scope_order) != len(set(scope_order)):
        raise ValueError("manifest scopeOrder 存在重复 scope")
    paths_by_scope = {
        path.relative_to(SOURCE_ROOT).with_suffix("").as_posix(): path
        for path in discovered_paths
    }
    declared = set(scope_order)
    discovered = set(paths_by_scope)
    if declared != discovered:
        missing = sorted(declared - discovered)
        extra = sorted(discovered - declared)
        raise ValueError(f"manifest 与页面源文件不一致：missing={missing}; extra={extra}")
    source_paths = [paths_by_scope[scope] for scope in scope_order]

    declared_scopes: set[str] = set()
    for path in source_paths:
        payload = read_json(path)
        meta = payload.get("_meta")
        strings = payload.get("strings")
        if not isinstance(meta, dict) or not isinstance(strings, dict):
            raise ValueError(f"源文件结构无效：{path}")
        scope = meta.get("scope")
        expected_scope = path.relative_to(SOURCE_ROOT).with_suffix("").as_posix()
        if scope != expected_scope:
            raise ValueError(f"scope 与路径不一致：{path} 声明 {scope!r}")
        if scope in declared_scopes:
            raise ValueError(f"重复 scope：{scope}")
        declared_scopes.add(scope)
        for key, localized in strings.items():
            if key in translations:
                raise ValueError(f"重复 key：{key} 同时位于 {ownership[key]} 和 {path}")
            if not isinstance(key, str) or not key:
                raise ValueError(f"空 key：{path}")
            if not isinstance(localized, dict):
                raise ValueError(f"译文必须是语言映射：{path}: {key}")
            actual_codes = set(localized)
            expected_codes = set(codes)
            if actual_codes != expected_codes:
                missing = sorted(expected_codes - actual_codes)
                extra = sorted(actual_codes - expected_codes)
                raise ValueError(f"语言集合错误：{key}; missing={missing}; extra={extra}")
            if not all(isinstance(localized[code], str) and localized[code] for code in codes):
                raise ValueError(f"译文必须是非空字符串：{path}: {key}")
            translations[key] = dict(localized)
            ownership[key] = scope

    english = {key: localized["en"] for key, localized in translations.items()}
    for key, localized in translations.items():
        english_format = format_signature(english[key])
        english_braces = Counter(BRACE_PATTERN.findall(english[key]))
        for code in codes:
            if format_signature(localized[code]) != english_format:
                raise ValueError(
                    f"C 格式符不一致：{key} [{code}] "
                    f"{format_signature(localized[code])} != {english_format}"
                )
            if Counter(BRACE_PATTERN.findall(localized[code])) != english_braces:
                raise ValueError(f"{{name}} 占位符不一致：{key} [{code}]")
    return manifest, codes, translations, ownership


def generated_payloads() -> tuple[dict[Path, dict[str, Any]], dict[str, str]]:
    manifest, codes, translations, ownership = load_sources()
    payloads: dict[Path, dict[str, Any]] = {}
    source_order = list(translations)
    expected_keys = set(source_order)
    meta_by_code = {item["code"]: item for item in manifest["languages"]}

    actual_pack_paths = set(LANGUAGE_ROOT.glob("*.json"))
    expected_pack_paths = {LANGUAGE_ROOT / f"{code}.json" for code in codes}
    extra_pack_paths = sorted(actual_pack_paths - expected_pack_paths)
    if extra_pack_paths:
        names = [path.name for path in extra_pack_paths]
        raise ValueError(f"存在 manifest 未声明的运行时语言包，请人工确认：{names}")

    for code in codes:
        path = LANGUAGE_ROOT / f"{code}.json"
        if path.exists():
            existing = read_json(path)
            existing_strings = existing.get("strings", {})
            if not isinstance(existing_strings, dict):
                raise ValueError(f"现有语言包 strings 无效：{path}")
            existing_order = list(existing_strings)
            ordered_keys = [key for key in existing_order if key in expected_keys]
            ordered_keys.extend(key for key in source_order if key not in existing_strings)
        else:
            ordered_keys = source_order
        strings = {key: translations[key][code] for key in ordered_keys}
        if set(strings) != expected_keys:
            raise ValueError(f"生成 key 集合失败：{code}")
        payloads[path] = {"_meta": meta_by_code[code], "strings": strings}
    return payloads, ownership


def check() -> None:
    payloads, ownership = generated_payloads()
    referenced = referenced_localization_keys()
    missing_references = sorted(referenced - set(ownership))
    if missing_references:
        raise ValueError(f"代码或 catalog 引用了不存在的本地化 key：{missing_references}")
    mismatches: list[str] = []
    for path, expected in payloads.items():
        if not path.exists():
            mismatches.append(f"缺少 {path.relative_to(ROOT)}")
            continue
        actual = read_json(path)
        if actual != expected:
            actual_strings = actual.get("strings", {})
            expected_strings = expected["strings"]
            changed = sorted(
                key for key in set(actual_strings) | set(expected_strings)
                if actual_strings.get(key) != expected_strings.get(key)
            )
            mismatches.append(
                f"{path.relative_to(ROOT)} 漂移 {len(changed)} 个 key: {changed[:8]}"
            )
    if mismatches:
        raise ValueError("源文件与运行时语言包不一致：\n  " + "\n  ".join(mismatches))
    print(
        f"通过：{len(ownership)} 个 key、{len(payloads)} 个语言包与页面化源文件一致；"
        f"{len(referenced)} 个代码/catalog 字面引用全部可解析"
    )


def referenced_localization_keys() -> set[str]:
    """Collect statically declared keys from Swift, the prototype and catalog."""
    keys: set[str] = set()
    swift_source = "\n".join(
        path.read_text(encoding="utf-8")
        for path in sorted((ROOT / "BatteryMonitor").rglob("*.swift"))
    )
    swift_patterns = (
        r'\bL\(\s*"([^"]+)"',
        r'\bdashboardText\(\s*"([^"]+)"',
        r'\bhardwareText\(\s*"([^"]+)"',
        r'\btext\(\s*"((?:p|hw|shell|menu|system|appearance|insight|stat|rt|hist|proc|condition)\.[^"]+)"',
    )
    for pattern in swift_patterns:
        keys.update(re.findall(pattern, swift_source))

    prototype_path = ROOT / "Prototype" / "build-prototype.py"
    if prototype_path.exists():
        prototype_text = prototype_path.read_text(encoding="utf-8")
        keys.update(re.findall(r'''\bt\(\s*["']([^"']+)["']''', prototype_text))
        module = ast.parse(prototype_text)
        call_key_positions = {"spec": (0,), "row": (3, 5)}
        for node in ast.walk(module):
            if not isinstance(node, ast.Call) or not isinstance(node.func, ast.Name):
                continue
            for index in call_key_positions.get(node.func.id, ()):
                if index >= len(node.args):
                    continue
                argument = node.args[index]
                if isinstance(argument, ast.Constant) and isinstance(argument.value, str):
                    keys.add(argument.value)

    catalog_path = ROOT / "BatteryMonitor" / "Resources" / "SystemFieldCatalog.json"
    if catalog_path.exists():
        catalog = read_json(catalog_path)
        key_fields = (
            "groupKey", "unitKey", "meaningKey", "reliabilityKey",
            "recommendationKey", "noteKey",
        )
        for field in catalog.get("fields", []):
            if not isinstance(field, dict):
                continue
            for name in key_fields:
                value = field.get(name)
                if isinstance(value, str) and value:
                    keys.add(value)
    return keys


def write() -> None:
    payloads, ownership = generated_payloads()
    changed = 0
    for path, payload in payloads.items():
        rendered = json.dumps(payload, ensure_ascii=False, indent=2) + "\n"
        before = path.read_text(encoding="utf-8") if path.exists() else None
        if before != rendered:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(rendered, encoding="utf-8")
            changed += 1
    print(f"已生成 {len(payloads)} 个语言包；改写 {changed} 个；共 {len(ownership)} 个 key")


def list_scopes() -> None:
    _, _, translations, ownership = load_sources()
    counts = Counter(ownership.values())
    for scope in SCOPE_SPECS:
        if scope in counts:
            print(f"{counts[scope]:4}  {scope}  {SCOPE_SPECS[scope]['title']}")
    unknown = sorted(set(counts) - set(SCOPE_SPECS))
    for scope in unknown:
        print(f"{counts[scope]:4}  {scope}")
    print(f"{len(translations):4}  TOTAL")


def source_usages(key: str) -> list[str]:
    candidates = [
        *sorted((ROOT / "BatteryMonitor").rglob("*.swift")),
        *sorted((ROOT / "Tests").rglob("*.swift")),
        ROOT / "Prototype" / "build-prototype.py",
        ROOT / "Prototype" / "battery-final-template.html",
        ROOT / "UI-MAP.md",
    ]
    needle = f'"{key}"'
    usages: list[str] = []
    for path in candidates:
        if not path.is_file():
            continue
        try:
            lines = path.read_text(encoding="utf-8").splitlines()
        except UnicodeDecodeError:
            continue
        for line_number, line in enumerate(lines, 1):
            if needle in line or (path.name == "UI-MAP.md" and key in line):
                usages.append(f"{path.relative_to(ROOT)}:{line_number}")
    return usages


def find(query: str) -> None:
    _, codes, translations, ownership = load_sources()
    matches = [key for key in translations if query.lower() in key.lower()]
    if not matches:
        raise ValueError(f"没有匹配的 key：{query}")
    for key in matches:
        print(f"{key}")
        print(f"  scope: {ownership[key]}")
        print(f"  source: Localization/Sources/{ownership[key]}.json")
        print(f"  zh-Hans: {translations[key].get('zh-Hans', '')}")
        print(f"  en: {translations[key].get('en', '')}")
        usages = source_usages(key)
        print(f"  usages: {', '.join(usages) if usages else '未发现字面引用（可能由数据驱动）'}")
        if len(codes) != len(translations[key]):
            print("  warning: 语言数量异常")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command")
    subparsers.add_parser("bootstrap", help="从现有语言包执行一次性页面化迁移")
    subparsers.add_parser("check", help="验证源文件并检查生成产物无漂移")
    subparsers.add_parser("write", help="从页面化源文件生成十个运行时语言包")
    subparsers.add_parser("list", help="列出页面/区块及 key 数量")
    find_parser = subparsers.add_parser("find", help="按 key 子串查询归属和引用")
    find_parser.add_argument("query")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    command = args.command or "check"
    try:
        if command == "bootstrap":
            bootstrap()
        elif command == "check":
            check()
        elif command == "write":
            write()
        elif command == "list":
            list_scopes()
        elif command == "find":
            find(args.query)
        else:
            raise ValueError(f"未知命令：{command}")
    except ValueError as error:
        print(f"错误：{error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
