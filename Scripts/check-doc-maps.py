#!/usr/bin/env python3
"""Validate progressive-disclosure docs, feature anchors, and current QA paths."""

from collections import Counter
import json
from pathlib import Path
import re


ROOT = Path(__file__).resolve().parent.parent

REQUIRED_PATHS = (
    "AGENTS.md",
    "CLAUDE.md",
    "CODE-MAP.md",
    "FEATURE-MAP.md",
    "UI-MAP.md",
    "LOCALIZATION.md",
    "QA-RUNBOOK.md",
    "QATests/TestKit/Config/QAConfig.example.plist",
    "QATests/TestKit/Scripts/build-user-test.sh",
    "QATests/TestKit/Scripts/load-qa-config.sh",
    "QATests/TestKit/Scripts/run-test-app.sh",
    "QATests/TestKit/Sources/Icon/main.swift",
    "QATests/TestKit/Sources/Insight/main.swift",
    "QATests/TestKit/Sources/Localization/main.swift",
    "Scripts/verify-release-app.sh",
)

DOCS_REQUIRING_RUNBOOK_LINK = (
    "AGENTS.md",
    "README.md",
    "README.zh-CN.md",
    "LOCALIZATION.md",
)

ACTIVE_TEXT = (
    "AGENTS.md",
    "CODE-MAP.md",
    "FEATURE-MAP.md",
    "UI-MAP.md",
    "QA-RUNBOOK.md",
    "README.md",
    "README.zh-CN.md",
    "LOCALIZATION.md",
    "Tools/README.md",
    "Scripts/verify-release-app.sh",
    "QATests/TestKit/Scripts/build-user-test.sh",
    "QATests/TestKit/Scripts/load-qa-config.sh",
    "QATests/TestKit/Scripts/run-test-app.sh",
)

STALE_REFERENCES = (
    "QATests/BuildValidation/AutomationHost",
    "QATests/BuildValidation/ReleaseCheck",
    "QATests/BatteryMonitor-UserTest.app",
    "QATests/QAConfig.local.plist",
    "./QATests/run-fixed-qa.sh",
    "./Scripts/run-test-app.sh",
    "./Scripts/build-user-test.sh",
    "./Scripts/verify-release.sh",
    '"$ROOT/Scripts/load-qa-config.sh"',
    "Tests/InsightTests.swift",
    "Tests/L10nTests.swift",
    "Tests/IconAlphaCheck.swift",
    "/tmp/icon_gen",
)

ENTRY_MAX_LINES = 100
ENTRY_MAX_BYTES = 12_000
ROUTER_REFERENCES = (
    "UI-MAP.md",
    "FEATURE-MAP.md",
    "CODE-MAP.md",
    "LOCALIZATION.md",
    "QA-RUNBOOK.md",
    "lookup-text",
)
FEATURE_TOKEN = re.compile(r"feature:[a-z0-9]+(?:[.-][a-z0-9]+)*")
FEATURE_ROW = re.compile(r"^\|\s*`(feature:[a-z0-9]+(?:[.-][a-z0-9]+)*)`\s*\|", re.MULTILINE)
FEATURE_ANCHOR = re.compile(r"([A-Za-z0-9_./+-]+\.swift)#([A-Za-z_][A-Za-z0-9_]*)")
INLINE_CODE = re.compile(r"`([^`\n]+)`")
DOC_CODE_PATH = re.compile(
    r"`((?:BatteryMonitor/)?(?:Models|Services|Views|Theme|Resources)/"
    r"[^`:#\s]+\.(?:swift|json))(?::[^`]*)?`"
)
LOCALIZATION_KEY = re.compile(
    r"(?:p|hw|shell|menu|system|appearance|insight|stat|rt|hist|proc|condition|"
    r"app|lang|tip|gauge|status)\.[A-Za-z0-9_.-]+"
)
UI_NON_LOCALIZATION_TOKENS = {"appearance.mode"}
LOCALIZATION_SCOPE_PREFIXES = (
    "app-shell/",
    "overview/",
    "technical/",
    "trends/",
    "diagnostics/",
    "settings/",
    "menubar/",
    "shared/",
    "catalogs/",
)


def read(relative: str) -> str:
    return (ROOT / relative).read_text(encoding="utf-8")


def resolve_doc_path(raw_path: str) -> Path:
    candidate = ROOT / raw_path
    if candidate.exists():
        return candidate
    if raw_path.startswith(("Models/", "Services/", "Views/", "Theme/", "Resources/")):
        return ROOT / "BatteryMonitor" / raw_path
    return candidate


def add_missing_path_failures(failures: list[str]) -> None:
    for relative in REQUIRED_PATHS:
        if not (ROOT / relative).is_file():
            failures.append(f"missing required file: {relative}")


def check_entry_size(failures: list[str]) -> None:
    agents = read("AGENTS.md")
    claude = read("CLAUDE.md")
    if agents != claude:
        failures.append("CLAUDE.md must resolve to the same thin router as AGENTS.md")
    line_count = len(agents.splitlines())
    byte_count = len(agents.encode("utf-8"))
    if line_count > ENTRY_MAX_LINES:
        failures.append(f"AGENTS.md is no longer thin: {line_count} lines > {ENTRY_MAX_LINES}")
    if byte_count > ENTRY_MAX_BYTES:
        failures.append(f"AGENTS.md is no longer thin: {byte_count} bytes > {ENTRY_MAX_BYTES}")
    for required in ROUTER_REFERENCES:
        if required not in agents:
            failures.append(f"AGENTS.md router is missing required entry: {required}")


def check_active_references(failures: list[str]) -> None:
    for relative in DOCS_REQUIRING_RUNBOOK_LINK:
        if "QA-RUNBOOK.md" not in read(relative):
            failures.append(f"{relative} does not link QA-RUNBOOK.md")

    for relative in ACTIVE_TEXT:
        path = ROOT / relative
        if not path.is_file():
            continue
        content = path.read_text(encoding="utf-8")
        for stale in STALE_REFERENCES:
            if stale in content:
                failures.append(f"{relative} still references stale path: {stale}")

    if (ROOT / "QATests" / "TestKit" / "README.md").exists():
        failures.append("QATests/TestKit/README.md duplicates the single QA-RUNBOOK.md")

    gitignore = read(".gitignore")
    for required_rule in ("QATests/Run/", "QATests/Personal/"):
        if required_rule not in gitignore:
            failures.append(f".gitignore is missing: {required_rule}")
    if re.search(r"^QATests/\s*$", gitignore, re.MULTILINE):
        failures.append(".gitignore still ignores the whole QATests tree")


def check_code_map(failures: list[str]) -> int:
    code_map = read("CODE-MAP.md")
    ui_map = read("UI-MAP.md")
    production_files = sorted((ROOT / "BatteryMonitor").rglob("*.swift"))
    coverage_text = code_map + "\n" + ui_map
    for path in production_files:
        if path.name not in coverage_text:
            failures.append(f"production Swift file is absent from maps: {path.relative_to(ROOT)}")

    for raw_path in sorted(set(DOC_CODE_PATH.findall(code_map + "\n" + ui_map))):
        if not resolve_doc_path(raw_path).is_file():
            failures.append(f"map references missing code/resource file: {raw_path}")
    return len(production_files)


def check_feature_map(failures: list[str]) -> tuple[int, int, int]:
    feature_map = read("FEATURE-MAP.md")
    ui_map = read("UI-MAP.md")
    definitions = FEATURE_ROW.findall(feature_map)
    counts = Counter(definitions)
    for feature_id, count in sorted(counts.items()):
        if count != 1:
            failures.append(f"Feature ID must have exactly one row: {feature_id} ({count})")

    defined = set(definitions)
    referenced = set(FEATURE_TOKEN.findall(ui_map))
    for feature_id in sorted(referenced - defined):
        failures.append(f"UI-MAP.md references undefined Feature ID: {feature_id}")
    for feature_id in sorted(defined - referenced):
        failures.append(f"FEATURE-MAP.md row is not reachable from UI-MAP.md: {feature_id}")

    anchors: set[tuple[str, str]] = set()
    for line_number, line in enumerate(feature_map.splitlines(), 1):
        current_path = None
        for token in INLINE_CODE.findall(line):
            full_anchor = FEATURE_ANCHOR.fullmatch(token)
            if full_anchor:
                current_path, symbol = full_anchor.groups()
                anchors.add((current_path, symbol))
                continue
            inherited = re.fullmatch(r"#([A-Za-z_][A-Za-z0-9_]*)", token)
            if inherited:
                if current_path is None:
                    failures.append(
                        f"orphan inherited feature symbol at FEATURE-MAP.md:{line_number}: {token}"
                    )
                else:
                    anchors.add((current_path, inherited.group(1)))

    sorted_anchors = sorted(anchors)
    for raw_path, symbol in sorted_anchors:
        path = resolve_doc_path(raw_path)
        if not path.is_file():
            failures.append(f"feature anchor path does not exist: {raw_path}#{symbol}")
            continue
        if symbol not in path.read_text(encoding="utf-8"):
            failures.append(f"feature anchor symbol does not exist: {raw_path}#{symbol}")

    file_references: set[str] = set()
    for token in INLINE_CODE.findall(feature_map):
        if "#" in token or "*" in token or " " in token:
            continue
        if token.startswith(LOCALIZATION_SCOPE_PREFIXES) and token.endswith(".json"):
            file_references.add(f"Localization/Sources/{token}")
        elif token.startswith(("Localization/", "QATests/", "Scripts/")) and token.endswith(
            (".json", ".swift", ".py", ".sh")
        ):
            file_references.add(token)
    for relative in sorted(file_references):
        if not (ROOT / relative).is_file():
            failures.append(f"FEATURE-MAP.md references missing support file: {relative}")
    return len(definitions), len(sorted_anchors), len(file_references)


def check_ui_localization_keys(failures: list[str]) -> int:
    authority_keys: set[str] = set()
    for path in sorted((ROOT / "Localization" / "Sources").rglob("*.json")):
        if path.name == "manifest.json":
            continue
        payload = json.loads(path.read_text(encoding="utf-8"))
        strings = payload.get("strings")
        if not isinstance(strings, dict):
            failures.append(f"localization source has no strings object: {path.relative_to(ROOT)}")
            continue
        authority_keys.update(strings)

    ui_tokens = {
        token
        for token in INLINE_CODE.findall(read("UI-MAP.md"))
        if LOCALIZATION_KEY.fullmatch(token)
    } - UI_NON_LOCALIZATION_TOKENS
    for key in sorted(ui_tokens - authority_keys):
        failures.append(f"UI-MAP.md references missing localization key: {key}")
    return len(ui_tokens)


def main() -> None:
    failures: list[str] = []
    add_missing_path_failures(failures)
    if failures:
        for failure in failures:
            print(f"ERROR: {failure}")
        raise SystemExit(1)

    check_entry_size(failures)
    check_active_references(failures)
    swift_count = check_code_map(failures)
    feature_count, anchor_count, feature_file_count = check_feature_map(failures)
    ui_key_count = check_ui_localization_keys(failures)

    if failures:
        for failure in failures:
            print(f"ERROR: {failure}")
        raise SystemExit(1)

    print(
        "渐进式文档检查通过："
        f"{swift_count} 个生产 Swift 文件已入图，"
        f"{feature_count} 个 Feature ID 可从 UI 到达，"
        f"{anchor_count} 个代码符号锚点可解析，"
        f"{feature_file_count} 个功能链支持文件存在，"
        f"{ui_key_count} 个 UI key 存在；QA 路径无漂移"
    )


if __name__ == "__main__":
    main()
