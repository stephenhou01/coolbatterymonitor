# Tools

## icon_gen.swift

Draws the app icon programmatically — rounded-rect gradient背景 + the
`battery.100.bolt` SF Symbol, tinted, with a soft top-left highlight and optional
glow. Renders at 1024×1024.

`BatteryMonitor/Assets.xcassets/AppIcon.appiconset/` holds the generated PNGs, so you only need
this when you want to change the icon's look rather than just rebuild the app.

This legacy source currently has no supported direct runner. Do not compile or
execute it from a system temporary directory, a hidden build directory, or an unsigned one-off binary.
If icon generation is reactivated, first add a stable, signed TestKit entry and
follow the single QA procedure in [`QA-RUNBOOK.md`](../QA-RUNBOOK.md); generated
sizes belong under `BatteryMonitor/Assets.xcassets/AppIcon.appiconset/`.

Rescued from the pre-Xcode-project version of this app (`build.sh` + `swiftc`
era), which is otherwise superseded. It was the only file there not represented
in this repository.

## analyze-session-tokens.py

Reports how many tokens a Claude Code session burned, per user turn, and writes a
chart. Nothing to do with the app — it's here because the answer is easy to get
wrong: the naive sum double-counts, since one API response is split across several
`.jsonl` lines that each carry the *same* `usage` object.

```bash
python3 Tools/analyze-session-tokens.py --list            # sessions for this project
python3 Tools/analyze-session-tokens.py 4b5260c3          # → QATests/Run/Reports/token-usage-<id>.html
python3 Tools/analyze-session-tokens.py 0f75c6eb -p /path/to/another/workspace   # another cwd's sessions
```

Deduplicates by `message.id`, and attributes each subagent's cost to the turn that
spawned it via `toolUseId`. The three numbers are not interchangeable: `total` sums
every call's whole context (so it counts re-reads), `ctx` is the peak single-call
context, `out` is output only. Typically ~85% of `total` is `cache_read` — the same
history read again, billed at a tenth.

HTML output lands in `QATests/Run/Reports/` (gitignored and disposable).

## AppIcon.icns

Prebuilt `.icns` from the same era. The Xcode build takes its icon from
`BatteryMonitor/Assets.xcassets`, so this is kept only for hand-rolled `.app` bundles (the
sibling DiskHealthCenter project still assembles bundles that way).
