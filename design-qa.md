# Design QA

## Sources

- Latest reference: `/var/folders/6x/5n5xzp595qq6yg5b59ph39vw0000gp/T/codex-clipboard-c620969d-69eb-4464-b452-468b75613b13.png`
- Implemented popup, light: `/tmp/BatteryMonitor-popup-top-toolbar-light-crop.png`
- Implemented popup, dark: `/tmp/BatteryMonitor-popup-top-toolbar-dark-crop.png`
- Side-by-side comparison: `/tmp/BatteryMonitor-reference-vs-implementation-dark.png`
- Five-page dark contact sheet: `/tmp/BatteryMonitor-five-pages-dark-contact.png`
- Technical page, light: `/tmp/BatteryMonitor-technical-light-live-final-3.png`

## Viewport and states checked

- Main window: 1240 × 860 points on a Retina display.
- Menu-bar panel: 440 points wide, both light and dark appearance.
- Menu-bar normal and customization states.
- Main navigation: Overview, Technical Details, Trends, Diagnostics, and Settings.
- Live system data, real application icons, non-zero CPU samples, and the empty-process fallback.

## Comparison findings

- The latest reference and implementation were placed in one side-by-side image before judging differences.
- The popup header now follows the requested order: identity, two-state light/dark switch, settings, language, collapse, and full quit.
- Settings, language, appearance, collapse, and quit no longer occupy the footer; the footer contains only “Open full dashboard”.
- The implementation keeps the reference's compact vertical rhythm, cyan/blue/green metric hierarchy, dividers, monospaced values, trend rows, and Top 3 application block.
- Light and dark appearances both retain readable semantic contrast. The complete Technical Details content remains scrollable and readable in both appearances.
- All five main-window pages render without clipping at the target viewport.

## Patches made during QA

- Replaced remaining hard-coded dark surfaces with adaptive semantic colors.
- Moved all utility controls into the popup header and reduced the popup appearance control to light/dark only.
- Added accessible selected-state reporting for appearance, explicit names for settings and language, and precise collapse/full-quit descriptions.
- Restored real app sampling and real application icons in Top 3; CPU values follow Activity Monitor's one-core-equals-100% convention.

## Final result

passed
