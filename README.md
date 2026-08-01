# CoolBatteryMonitor

Privacy policy and support page.

> The privacy policy / support page lives in `index.html` and is served by GitHub
> Pages at <https://stephenhou01.github.io/coolbatterymonitor/>. Do not remove or
> rename that file, and keep this repository public — GitHub Pages is unavailable
> for private repositories on the Free plan, and the App Store submission points
> at that URL.

---

A native macOS battery dashboard built with SwiftUI. Reads battery telemetry
straight from IOKit (`AppleSmartBattery`) and enumerates processes via
`proc_listpids` / `proc_pidinfo` — no shelling out, no helper daemons.

## Features

- **Menu-bar first glance** — keeps charge and system time remaining visible without opening the dashboard; clicking it expands health, power, cycles and temperature, while AC estimates remain explicitly labelled as unplug forecasts
- **Remaining time first** — uses macOS `TimeRemaining` / `AvgTimeToEmpty` directly while on battery; clearly labels the current-load estimate shown while plugged in
- **System-aligned live data** — charge level, health, direct system power, temperature and model-specific battery specifications
- **Runtime history** — stores valid system estimates at the battery gauge's roughly 56-second refresh cadence; no duplicate high-frequency samples
- **10-second power center** — plots whole-computer power and places active processes beside it as CPU/memory context, without inventing per-process wattage; automatic refresh can be paused or resumed
- **Capacity explanation** — design capacity, current full capacity, current charge, used-since-full capacity and permanent loss in one consistent visualization
- **Official comparison** — for supported models, compares the current battery with Apple's published battery energy and test runtimes without presenting those lab figures as a promise
- **Curated evidence table** — 74 audited raw/public/derived metrics with live values, ranges, reliability and formula help
- **Four-layer system verifier** — a 464-field metadata catalog for IOPowerSources, AppleSmartBattery/IORegistry, legacy IOPM and ProcessInfo, merged with every live field macOS returns; tabs cover meaningful fields, anomalies, each source and all fields
- **10 languages** with runtime switching (see below)

## Requirements

macOS 14.0+, on Apple silicon or Intel Macs. The Release configuration builds a
universal `arm64` + `x86_64` app. Sandboxed, hardened runtime.

## Build

The Xcode project is generated from `project.yml`, so edit that rather than the
`.xcodeproj`:

```bash
brew install xcodegen
xcodegen generate
xcodebuild -project BatteryMonitor.xcodeproj -scheme BatteryMonitor -configuration Debug build
```

## Localization

Translations are **not** in the Swift source. Each language is a self-describing
JSON pack under `Localization/Languages/`, bundled as a folder reference so the
directory structure survives into `BatteryMonitor.app/Contents/Resources/Languages/`:

```json
{
  "_meta": { "code": "zh-Hans", "name": "简体中文", "order": 20 },
  "strings": { "app.title": "电池监控中心", "...": "..." }
}
```

`_meta.name` is the endonym — the language's own name for itself, shown in the
in-app switcher. `order` exists because endonyms have no meaningful sort order
across scripts.

### Adding a language

Drop one JSON file into `Localization/Languages/` and rebuild. No Swift changes,
no `project.yml` changes, no `xcodegen` re-run — the switcher discovers packs at
launch. Optionally add a matching `BatteryMonitor/<code>.lproj/InfoPlist.strings`
so the Finder/Dock name matches too; that part *does* require re-running xcodegen.

### Changing translations without rebuilding

Packs in `Application Support/BatteryMonitor/Languages/` override bundled ones of
the same code, merged per key. Useful for iterating on wording.

### Notes

- Language resolution defaults to the system language via
  `Bundle.preferredLocalizations(from:)`, which handles `pt-BR → pt`,
  `en-GB → en`, `zh-Hans-CN → zh-Hans`. English is only the last-resort fallback.
- Packs are untrusted input, so format specifiers are validated against the `en`
  pack at load time. `String(format:)` is a C variadic — a pack that wrote `%d`
  where the code passes a `Double` would be memory-unsafe. Mismatched keys are
  dropped individually and fall back to `en`.
- The Dock / menu bar name always follows the *system* language, not the in-app
  choice: `CFBundleDisplayName` is read by the OS at launch and cannot change at
  runtime.

## Tests

```bash
./Tests/run-insight-tests.sh
./Tests/run-l10n-tests.sh
```

The insight test compiles the real model and analysis code. The localization
test compiles `Localization.swift` into a throwaway `.app` bundle and exercises
pack loading, ordering, key fallback, locale-aware number formatting, the
Application Support override layer, and the format-specifier guard. Both tests
use isolated temporary directories; they never write to or delete the user's
real `~/Library/Application Support/BatteryMonitor` data.

For the complete local pre-release check (configuration, plist files, language
packs, an unsigned Universal Release build, and both test suites), run:

```bash
./Scripts/verify-release.sh
```

This check neither changes the version/build number nor uploads anything. Since
`project.yml` is authoritative, run `xcodegen generate` before this check and
again whenever the project specification or source-file list changes.

`BatteryMonitor/Resources/SystemFieldCatalog.json` contains field metadata only;
the app never displays the workbook's saved sample values. To regenerate the
catalog from an artifact-tool workbook export, use
`Scripts/generate-system-field-catalog.py`.

## Privacy

The developer does not collect or receive personal data, and the app has no
network access. Charging history, battery samples, and language preferences are
stored only on the user's Mac inside the app's sandboxed container.
