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

- **Live gauge** — charge level, charge/discharge wattage, cell temperature, cycle count
- **Real-time charts** — voltage / current / power / temperature / level, sampled every 3s over a 30s–3m window (Swift Charts)
- **Battery health** — max vs. design capacity, cycle-count assessment, system condition
- **Charge history** — self-recorded charging sessions with rate comparison, cached in Application Support
- **Power-hungry processes** — top CPU consumers with expandable per-process CPU sparklines
- **10 languages** with runtime switching (see below)

## Requirements

macOS 14.0+, Apple silicon. Sandboxed, hardened runtime.

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
./Tests/run-l10n-tests.sh
```

Compiles the real `Localization.swift` into a throwaway `.app` bundle and
exercises pack loading, ordering, key fallback, locale-aware number formatting,
the Application Support override layer, and the format-specifier guard.
