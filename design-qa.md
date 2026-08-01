# Design QA

## Sources

- Latest glass-material reference: `/var/folders/6x/5n5xzp595qq6yg5b59ph39vw0000gp/T/codex-clipboard-272e7003-d9d1-4969-a6c2-48b7e9d566f8.png`
- Implemented glass popup, dark: `/tmp/BatteryMonitor-glass-dark-lake-final.png`
- Implemented glass popup, light: `/tmp/BatteryMonitor-glass-light-lake-final.png`
- Full reference/implementation comparison: `/tmp/BatteryMonitor-glass-reference-vs-implementation.png`
- Focused glass-material comparison: `/tmp/BatteryMonitor-glass-focused-comparison.png`
- Earlier live popup, light: `/tmp/BatteryMonitor-popup-top-toolbar-light-crop.png`
- Earlier live popup, dark: `/tmp/BatteryMonitor-popup-top-toolbar-dark-crop.png`
- Five-page dark contact sheet: `/tmp/BatteryMonitor-five-pages-dark-contact.png`
- Technical page, light: `/tmp/BatteryMonitor-technical-light-live-final-3.png`

## Viewport and states checked

- Main window: 1240 × 860 points on a Retina display.
- Menu-bar panel: 440 × 745 points at 2×, both light and dark appearance.
- Material QA used the real menu-bar view over a controlled lake background, so backdrop transmission and tint could be compared while the interactive desktop was locked.
- Menu-bar normal and customization states.
- Main navigation: Overview, Technical Details, Trends, Diagnostics, and Settings.
- Live system data, real application icons, non-zero CPU samples, and the empty-process fallback.

## Comparison findings

- The supplied source and implemented popup were placed in the same full and focused comparison images before judging the result.
- The panel now transmits the lake's blue/green environment color through a native ultra-thin material instead of painting an opaque app background.
- The reference's continuous rounded silhouette, thin luminous edge, soft backdrop blur, cool cyan tint, and subtle top-left highlight are all present. The app intentionally keeps its denser information layout.
- Dark appearance remains readable over a colorful desktop; light appearance adds enough neutral material to keep black text and dividers legible without hiding the background.
- The popup header still follows the requested order: identity, two-state light/dark switch, settings, language, collapse, and full quit. The off-screen renderer cannot execute native `Menu` controls and shows unavailable placeholders for those two controls; their production behavior was already checked in the earlier live captures and their implementation was not changed by this material pass.
- The complete Technical Details content and all five main-window pages remain unchanged and accessible.

## Patches made during QA

- Made the menu-bar hosting window transparent while preserving its selected light/dark appearance.
- Replaced the opaque popup surface with native `.ultraThinMaterial`, adaptive blue/cyan tint layers, a soft radial highlight, a thin bright border, and a restrained shadow.
- Kept every existing metric, trend, Top 3 process, language/appearance control, and click action unchanged.
- Extended the snapshot harness with an optional real-background input so future material QA can run reproducibly even when the desktop session is locked.

## Final result

passed
