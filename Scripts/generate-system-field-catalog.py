#!/usr/bin/env python3
"""Generate the in-app four-layer field catalog from an artifact-tool export.

The workbook's sample values are intentionally discarded.  The generated file
only carries field names and explanatory metadata; live values are always read
from macOS by SystemDataCollector.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit("usage: generate-system-field-catalog.py WORKBOOK_DATA_JSON OUTPUT_JSON")

    source = Path(sys.argv[1])
    output = Path(sys.argv[2])
    sheets = json.loads(source.read_text(encoding="utf-8"))
    field_sheet = next(sheet for sheet in sheets if sheet["name"] == "字段总表")

    fields = []
    for row in field_sheet["values"][4:]:
        if not row or len(row) < 13 or not row[3]:
            continue
        stars = str(row[11] or "").count("★")
        fields.append({
            "layer": int(row[0]),
            "source": str(row[1]),
            "group": str(row[2] or "其他"),
            "path": str(row[3]),
            "declaredType": str(row[5] or "Unknown"),
            "unit": "" if row[6] in (None, "—") else str(row[6]),
            "meaning": str(row[7] or "未找到公开定义；仅保留用于本机诊断与趋势观察。"),
            "reliability": str(row[8] or "未核验"),
            "recommendation": str(row[10] or "补充使用"),
            "valueStars": stars,
            "note": str(row[12] or ""),
        })

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
