# CoolBatteryMonitor

[简体中文](README.zh-CN.md) · **English**

A native macOS battery dashboard built with SwiftUI. It reads battery telemetry
straight from IOKit and shows you what the system actually reports — including
where the system reports nothing at all.

The guiding rule: **never fabricate a number to fill a gap.** Where a value is
measured, it says so. Where it is derived, it shows the formula. Where the data
is not there yet, it says "collecting" instead of guessing.

---

## Interface

### Menu bar

Charge and remaining time stay visible without opening anything. Clicking expands
a panel with health, power draw, cycle count and temperature, plus the top
processes by CPU. While plugged in, any runtime figure is labelled explicitly as
an *unplug forecast* rather than presented as time remaining.

```
▸ Menu bar item        86%  ·  4:12
  └ popover            health · power · cycles · temperature
                       top processes · runtime sparkline
```

### Dashboard — five pages

```
Overview      Charge ring + 8 headline metrics + charge/discharge timeline
Technical     Power center (10-second curve + process activity)
              Capacity breakdown (design / full / current / loss)
              Official comparison against Apple's published figures
              System data workbench (464-field four-layer verifier)
Trends        Live monitor · runtime history · process ranking · charge history
Diagnostics   Health diagnosis · power analysis · adapter check
              Charging habits · system anomalies
Settings      Language · appearance · menu-bar layout · refresh cadence
```

Every metric carries a **?** button that opens a drawer with the raw IOKit field
names, the substituted formula, the value's reliability tier, and when the field
was last read.

---

## Features

**Battery health and capacity**
- Charge level, health percentage, cycle count, temperature and per-cell voltages
- Capacity explained as one consistent picture: factory design capacity → today's
  full-charge capacity → current charge → used since full → long-term loss, with
  the "temporarily unreachable" and "genuinely aged" parts separated
- Age estimation from cycle count and capacity retention, marked as an estimate
  rather than a hardware-decoded date
- Comparison against Apple's published battery energy and lab runtimes for
  supported models, without presenting lab figures as a promise

**Power and processes**
- Whole-computer power draw read from IOKit, cross-checked across three fields
  (`SystemPower`, `SystemLoad`, and input voltage × current)
- A 10-second power curve with pause/resume
- Process ranking by CPU, with child processes rolled up into their parent app
  so one browser or editor is one row instead of thirty
- Whole-machine CPU alongside a visible/system split, because a sandboxed app
  cannot read root-owned processes — the gap is labelled, not hidden
- **No per-process wattage.** macOS does not expose a reliable per-process power
  figure, so the app does not invent one; CPU and memory are shown as workload
  context

**Runtime estimates**
- Uses the system's own `TimeRemaining` / `AvgTimeToEmpty` while on battery
- Stores valid estimates at the battery gauge's real refresh cadence (~56 s)
  rather than duplicating high-frequency samples
- Distinguishes a median-power estimate from a current-load estimate and says
  which one is on screen

**Transparency tooling**
- A curated evidence table of audited raw, public and derived metrics with live
  values, expected ranges and reliability tiers
- A four-layer system verifier: a 464-field metadata catalog covering
  IOPowerSources, AppleSmartBattery / IORegistry, legacy IOPM and process
  information, merged with every live field macOS returns. Tabs separate
  meaningful fields, anomalies, each individual source, and everything

**Charging habits**
- Weekly report on charge sessions, average high/low state of charge, peak
  charging temperature
- Habit scoring that only appears once enough days have actually been observed

---

## Languages

Ten languages with runtime switching — no relaunch:

English · 简体中文 · 繁體中文 · 日本語 · 한국어 · Deutsch · Español · Français ·
Italiano · Português

Each language is a self-describing JSON pack, so translations live outside the
Swift source and a new language is one file.

---

## Requirements

- macOS 14.0 or later
- Apple silicon and Intel Macs (temperature units and CPU timebase differ between
  the two; both are handled)
- App Sandbox and Hardened Runtime enabled
- **No network access at all**

Current version: 1.2.0

---

## Privacy

The developer does not collect or receive any personal data, and the app has no
network access. Charging history, battery samples and language preferences are
stored only on your Mac, inside the app's sandboxed container.

Full policy: <https://stephenhou01.github.io/coolbatterymonitor/>

---

## Building from source

The Xcode project is generated from `project.yml` — edit that rather than the
`.xcodeproj`:

```bash
brew install xcodegen
xcodegen generate
xcodebuild -project BatteryMonitor.xcodeproj -scheme BatteryMonitor \
           -configuration Debug build
```

Tests:

```bash
./QATests/run-fixed-qa.sh all  # fixed signed QA Host: icon + logic + localization
./Scripts/verify-release.sh    # full local pre-release check, uploads nothing
```

The runtime suite always overwrites the same signed app at
`QATests/BuildValidation/AutomationHost/BatteryMonitor-QAHost.app`, runs it, and
closes it before returning. Pass `icon`, `insight`, or `l10n` instead of `all`
to run one phase.

Built-in copy is maintained by page and section under `Localization/Sources/`.
Run `python3 Localization/build-language-packs.py write` to generate the ten
runtime packs; adding a language means adding its metadata to
`Localization/Sources/manifest.json`
and a translation to every source entry. No Swift change or `xcodegen` re-run is
needed. Generated packs are still treated as untrusted input at runtime: format
specifiers are validated against English because `String(format:)` is C variadic.

---

> **Repository note** — the privacy policy and support page live in `index.html`,
> served by GitHub Pages at the URL above. Do not remove or rename that file, and
> keep this repository public: GitHub Pages is unavailable for private
> repositories on the Free plan, and the App Store submission points at that URL.
