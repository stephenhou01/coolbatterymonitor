# Design QA

## Sources

- Latest six-metric help reference: `/var/folders/6x/5n5xzp595qq6yg5b59ph39vw0000gp/T/codex-clipboard-55a7ca7b-8878-4011-9b57-8c49309fe05e.png`
- Implemented overview with six help buttons: `/Users/stephen/Desktop/BatteryMonitor/.build/qa/BatteryMonitor-overview-help-buttons.png`
- Implemented lowest-level field drawer: `/Users/stephen/Desktop/BatteryMonitor/.build/qa/BatteryMonitor-overview-help-drawer.png`
- Combined metric reference/implementation comparison: `/Users/stephen/Desktop/BatteryMonitor/.build/qa/BatteryMonitor-overview-reference-vs-implementation.png`
- Latest App icon source: `/var/folders/6x/5n5xzp595qq6yg5b59ph39vw0000gp/T/codex-clipboard-88fb0b32-2e66-450e-99de-32b9f2238aa1.png`
- Combined App icon source/1024 implementation comparison: `/Users/stephen/Desktop/BatteryMonitor/.build/qa/BatteryMonitor-icon-reference-vs-implementation.png`
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

- Overview QA: 1080 × 800 points at 2×, normal state and charging-power help drawer open.
- App icon QA: exact square source compared against the generated 1024×1024 RGBA master; all seven asset sizes were inspected for dimensions and alpha.
- Main window: 1240 × 860 points on a Retina display.
- Menu-bar panel: 440 × 745 points at 2×, both light and dark appearance.
- Material QA used the real menu-bar view over a controlled lake background, so backdrop transmission and tint could be compared while the interactive desktop was locked.
- Menu-bar normal and customization states.
- Main navigation: Overview, Technical Details, Trends, Diagnostics, and Settings.
- Live system data, real application icons, non-zero CPU samples, and the empty-process fallback.

## Comparison findings

- Each of the six overview metric tiles now has the same restrained circular `?` affordance in its top-right corner without moving the icon, title, value, or hint.
- Opening a metric shows only that metric's consumer explanation, current result, lowest-level IOKit fields, formula, current-machine substitution, and source/reliability. The charging-power state was rendered with live values and all blocks visible.
- The supplied pink battery artwork is preserved without recropping or redrawing. The 1024 master and 16/32/64/128/256/512 derivatives retain the source composition and an alpha channel required by the release verifier.
- The supplied source and implemented popup were placed in the same full and focused comparison images before judging the result.
- The panel now transmits the lake's blue/green environment color through a native ultra-thin material instead of painting an opaque app background.
- The reference's continuous rounded silhouette, thin luminous edge, soft backdrop blur, cool cyan tint, and subtle top-left highlight are all present. The app intentionally keeps its denser information layout.
- Dark appearance remains readable over a colorful desktop; light appearance adds enough neutral material to keep black text and dividers legible without hiding the background.
- The popup header still follows the requested order: identity, two-state light/dark switch, settings, language, collapse, and full quit. The off-screen renderer cannot execute native `Menu` controls and shows unavailable placeholders for those two controls; their production behavior was already checked in the earlier live captures and their implementation was not changed by this material pass.
- The complete Technical Details content and all five main-window pages remain unchanged and accessible.

## Patches made during QA

- Added help affordances and dedicated field/formula definitions for current power, adapter power, charging power, temperature, cycles, and health.
- Added native help text for the three new metric definitions to all ten language packs.
- Replaced the complete AppIcon asset set and `Tools/AppIcon.icns` with the supplied pink battery artwork.
- Moved executable test artifacts and QA captures into the repository's fixed `.build/` tree; compiled test executables are signed with the existing Apple Development identity before execution.
- Made the menu-bar hosting window transparent while preserving its selected light/dark appearance.
- Replaced the opaque popup surface with native `.ultraThinMaterial`, adaptive blue/cyan tint layers, a soft radial highlight, a thin bright border, and a restrained shadow.
- Kept every existing metric, trend, Top 3 process, language/appearance control, and click action unchanged.
- Extended the snapshot harness with an optional real-background input so future material QA can run reproducibly even when the desktop session is locked.

## Final result

passed
