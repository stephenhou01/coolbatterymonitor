#!/usr/bin/env python3
"""Compatibility entry point for the old localization sync command.

The editing authority moved to Localization/Sources, grouped by page and
section.  Keep this filename so existing local workflows fail forward into the
unified generator instead of silently reviving EXTRA / APP_EXTRA.
"""

from pathlib import Path
import subprocess
import sys


ROOT = Path(__file__).resolve().parents[1]
BUILDER = ROOT / "Localization" / "build-language-packs.py"


def main() -> int:
    print(
        "sync-prototype-strings.py 已兼容转发到页面化本地化生成器；"
        "后续请直接使用 build-language-packs.py write",
        flush=True,
    )
    return subprocess.call([sys.executable, str(BUILDER), "write"], cwd=ROOT)


if __name__ == "__main__":
    raise SystemExit(main())
