#!/usr/bin/env python3
"""Generate the in-app four-layer field catalog from an artifact-tool export.

The workbook's sample values are intentionally discarded.  The generated file
only carries field names and explanatory metadata; live values are always read
from macOS by SystemDataCollector.

Localization
------------
Six of the emitted columns (group / unit / meaning / reliability /
recommendation / note) are shown in the four-layer workbench and therefore have
to be translatable.  The workbook only ever contains Chinese, so each of those
values also gets a `*Key` pointing at a language-pack entry, resolved through
`system-field-catalog-keys.json`.

The Chinese raw values stay in the output on purpose: they are the zh-Hans copy
*and* the tokens `SystemFieldMetadata.isMeaningfulByDefault` and
`SystemFieldValueConversion` match against.

Any raw value missing from the key map is a hard error.  Emitting a field with
no `*Key` would look perfectly fine in the UI — it silently falls back to the
Chinese raw value in all ten languages — so failing loudly is the only way a
future workbook swap cannot quietly un-localize the table.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

KEY_MAP_PATH = Path(__file__).resolve().parent / "system-field-catalog-keys.json"

# Blank workbook cells fall back to these.  They are deliberately absent from the
# key map: the current 464 rows never hit them, and if a future workbook does, the
# unmapped-value check below fires so whoever regenerates has to add the key plus
# ten translations rather than shipping an untranslatable row.
FALLBACK_GROUP = "其他"
FALLBACK_MEANING = "未找到公开定义；仅保留用于本机诊断与趋势观察。"
FALLBACK_RELIABILITY = "未核验"
FALLBACK_RECOMMENDATION = "补充使用"

# (raw column, emitted key column).  Empty raw value -> no key, which the app reads
# as "the raw value is the answer" (that path also serves fields macOS adds at
# runtime, which arrive already localized and with no key at all).
LOCALIZED_COLUMNS = (
    ("group", "groupKey"),
    ("unit", "unitKey"),
    ("meaning", "meaningKey"),
    ("reliability", "reliabilityKey"),
    ("recommendation", "recommendationKey"),
    ("note", "noteKey"),
)


def load_key_map() -> dict[str, str]:
    if not KEY_MAP_PATH.is_file():
        raise SystemExit(
            f"missing key map: {KEY_MAP_PATH}\n"
            "It maps each Chinese catalog value to its language-pack key. Without it the "
            "generated catalog would carry no *Key at all and the workbench would show "
            "Chinese in every language."
        )
    payload = json.loads(KEY_MAP_PATH.read_text(encoding="utf-8"))
    mapping = payload["map"]
    assert isinstance(mapping, dict) and mapping, f"empty key map in {KEY_MAP_PATH}"
    return mapping


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit("usage: generate-system-field-catalog.py WORKBOOK_DATA_JSON OUTPUT_JSON")

    source = Path(sys.argv[1])
    output = Path(sys.argv[2])
    key_map = load_key_map()
    sheets = json.loads(source.read_text(encoding="utf-8"))
    field_sheet = next(sheet for sheet in sheets if sheet["name"] == "字段总表")

    fields = []
    unmapped: dict[str, list[str]] = {}
    for row in field_sheet["values"][4:]:
        if not row or len(row) < 13 or not row[3]:
            continue
        stars = str(row[11] or "").count("★")
        field = {
            "layer": int(row[0]),
            "source": str(row[1]),
            "group": str(row[2] or FALLBACK_GROUP),
            "path": str(row[3]),
            "declaredType": str(row[5] or "Unknown"),
            "unit": "" if row[6] in (None, "—") else str(row[6]),
            "meaning": str(row[7] or FALLBACK_MEANING),
            "reliability": str(row[8] or FALLBACK_RELIABILITY),
            "recommendation": str(row[10] or FALLBACK_RECOMMENDATION),
            "valueStars": stars,
            "note": str(row[12] or ""),
        }
        for raw_column, key_column in LOCALIZED_COLUMNS:
            raw = field[raw_column]
            if not raw:
                # Written as "" rather than omitted so every field carries the same
                # 17 keys; the app reads empty and absent identically.
                field[key_column] = ""
                continue
            key = key_map.get(raw)
            if key is None:
                unmapped.setdefault(raw, []).append(f"{field['path']}.{raw_column}")
                continue
            field[key_column] = key
        fields.append(field)

    if unmapped:
        lines = [
            f"{len(unmapped)} catalog value(s) have no language-pack key. Refusing to write "
            f"{output} — emitting them would silently show Chinese in all ten languages.",
            "",
            "Add each to Scripts/system-field-catalog-keys.json, then translate the new key in "
            "Localization/Sources/catalogs/system-fields.json and regenerate the language packs:",
            "",
        ]
        for raw, where in sorted(unmapped.items()):
            lines.append(f"  {raw!r}\n      first seen at {where[0]} ({len(where)} field(s))")
        raise SystemExit("\n".join(lines))

    payload = {
        "schemaVersion": 1,
        "fieldCount": len(fields),
        "sourceWorkbook": "BatteryMonitor-四层电池电源全字段-20260731.xlsx",
        "fields": fields,
    }
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"generated {len(fields)} metadata rows -> {output}")


if __name__ == "__main__":
    main()
