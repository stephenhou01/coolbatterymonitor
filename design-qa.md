# Localized Raw-Field Explanations Design QA

## Source and implementation

- Source visual truth: `/var/folders/6x/5n5xzp595qq6yg5b59ph39vw0000gp/T/codex-clipboard-180b075d-c9ed-4fb3-9954-a29ede4430d4.png`.
- Dark implementation: `.build/qa/metric-help-field-explanations-dark.png`.
- Light implementation: `.build/qa/metric-help-field-explanations-light.png`.
- Full-view and focused comparison: `.build/qa/metric-help-field-explanations-reference-vs-implementation.png`; the drawer is the only changed component, so one same-scale side-by-side comparison covers both levels.
- Viewport: 1080 × 900 points at 2× density; comparison uses the top 512-point drawer region from both images.
- State: current-power help drawer expanded with all six raw inputs visible in the full implementation capture.

## Findings

- P0: none.
- P1: none.
- P2: none.
- P3: none.

## Fidelity checks

- Fonts and typography: the plain-language explanation uses the existing system face and semibold hierarchy; the technical field name remains monospaced, selectable, and visually secondary; numeric values retain the existing monospaced cyan treatment.
- Spacing and layout rhythm: each raw-field card now has a stable two-line label stack with the value aligned at the trailing edge. Long names and values fit without clipping, and the drawer remains scrollable at the reference height.
- Colors and visual tokens: all foregrounds, borders, fills, and cyan emphasis reuse existing adaptive theme tokens and remain legible in dark and light appearances.
- Image and asset quality: this text-only component introduces no new imagery, icons, placeholders, or approximated assets.
- Copy and content: every expanded raw field displays an understandable explanation in the selected language while retaining the exact system parameter underneath. The six reported power fields have specific descriptions; uncommon future fields receive a localized diagnostic fallback instead of a blank label.
- Interaction and accessibility: selection, scrolling, backdrop close, close button, Escape handling, and text selection remain unchanged. The explanation is regular SwiftUI text and participates in the drawer's accessibility tree.

## Patches made since the previous QA pass

- Reworked every raw-field row into plain-language explanation, technical parameter, and raw value hierarchy.
- Added semantic explanation routing for power, voltage, current, accumulated telemetry, capacity, time, temperature, cell, resistance, adapter, cycle, state, model reference, and derived fields.
- Added native explanation copy for all ten language packs plus a localized fallback for new or uncommon fields.
- Added semantic, localization-completeness, non-English-fallback, dark/light snapshot, and release-build verification.

final result: passed

---

# Adapter Output And Battery Charging Power Design QA

## Source and implementation

- Source visual truth: `/var/folders/6x/5n5xzp595qq6yg5b59ph39vw0000gp/T/codex-clipboard-be483634-4aa0-44cd-93e2-5988537ff504.png` for the established overview rail, and `/var/folders/6x/5n5xzp595qq6yg5b59ph39vw0000gp/T/codex-clipboard-2af32fdd-8ba5-43c6-af86-ee3da7ac0b7f.png` for the reported charging-power contradiction.
- Same-viewport baseline: `.build/qa/BatteryMonitor-overview-help-buttons.png`.
- Dark implementation: `.build/qa/power-cards/overview-dark.png`.
- Light implementation: `.build/qa/power-cards/overview-light.png`.
- Compact implementation: `.build/qa/power-cards/overview-compact-dark.png`.
- Adapter-output drawer: `.build/qa/power-cards/adapter-output-dark.png`.
- Battery-charging drawer: `.build/qa/power-cards/battery-charging-dark.png`.
- Full-view comparison: `.build/qa/power-cards/overview-reference-vs-implementation.png`.
- Focused comparison: `.build/qa/power-cards/charging-source-vs-implementation.png`.
- Viewports: 1080 × 800 points in dark/light and 720 × 900 points for the compact fallback, rendered at 2× density.
- State: live overview plus a deterministic 65 W adapter fixture with `SystemPowerIn = 16,200 mW`, battery voltage `12,466 mV`, battery current `0 mA`, and `IsCharging = false`.

## Findings

- P0: none.
- P1: none.
- P2: none.
- P3: the compact four-column fallback leaves the final grid cell empty because seven metrics wrap as 4 + 3. This is an acceptable consequence of preserving readable card widths instead of squeezing seven labels into the minimum window.

## Fidelity checks

- Fonts and typography: the new card uses the existing rounded numeric face and the drawers retain monospaced raw fields and formulas. The longer adapter-output title wraps without clipping at both viewports.
- Spacing and layout rhythm: the preferred viewport preserves the one-row rail; the compact viewport changes to a 4 + 3 grid with the same card height, padding, radii, dividers, and question-mark placement.
- Colors and visual tokens: the adapter-output card uses the existing cyan input-flow token, while battery charging retains green. Dark and light surfaces remain legible with no hard-coded theme regression.
- Image and icon quality: the new adapter-output glyph is a native SF Symbol resolved through the shared macOS 14-compatible icon system. No raster placeholder, custom SVG, or mismatched asset was introduced.
- Copy and content: the three power concepts are now explicit: 65 W adapter rating, 16.2 W whole-Mac adapter output, and 0 W battery charging. The battery drawer proves `12.466 V × 0 A = 0 W` and contains no `SystemPowerIn` field.
- Interaction: all seven question-mark buttons remain available. The adapter-output and battery-charging drawers use the established glass panel, scroll, close, backdrop, Escape, and text-selection behavior.

## Patches made since the previous QA pass

- Added a dedicated adapter-output card and explanation sourced from `PowerTelemetryData.SystemPowerIn`.
- Replaced the charging card calculation with battery pack voltage × positive battery current.
- Added an adaptive seven-column / four-column metric rail, a distinct compatible icon, ten-language copy, and semantic regression tests.

final result: passed

---

# Native Frosted Menu Panel Design QA

## Source and implementation

- Source visual truth: `/var/folders/6x/5n5xzp595qq6yg5b59ph39vw0000gp/T/codex-clipboard-272e7003-d9d1-4969-a6c2-48b7e9d566f8.png` for the requested translucent weather-widget glass, and `/var/folders/6x/5n5xzp595qq6yg5b59ph39vw0000gp/T/codex-clipboard-3f3297e1-14a5-4540-bd42-ce551deac1a9.png` for the reported flat-gray failure.
- Live implementation screenshot: `.build/qa/glass-panel/menu-glass-wallpaper-panel.png`.
- Full desktop evidence: `.build/qa/glass-panel/menu-glass-wallpaper-full.png`.
- Same-input comparison: `.build/qa/glass-panel/glass-reference-vs-implementation.png`.
- State: Apple Development-signed Debug app, dark appearance, real `MenuBarExtra` window, colorful desktop directly behind the panel, and inline metric-editing controls visible.

## Findings

- P0: none.
- P1: none.
- P2: none.
- P3: the material intentionally blurs text and icon detail behind the panel instead of leaving it readable. Large desktop color regions remain visible, matching the privacy and legibility behavior of native macOS glass.

## Fidelity checks

- Material: the former SwiftUI material fallback was replaced with an active `NSVisualEffectView` using `.popover` and `.behindWindow`, so the window samples and blurs the actual desktop underneath it.
- Transparency: the dark cyan and light blue tint layers were reduced to accents instead of opaque fills. The live capture visibly carries the lake blue, rock gray, and green water through the panel.
- Legibility: primary labels, live values, separators, edit controls, and the bottom action retain sufficient contrast across both bright water and dark rock regions.
- Shape and edge treatment: the existing 22-point continuous radius, thin adaptive highlight border, and soft external shadow remain intact without an opaque rectangle outside the rounded mask.
- Interaction: appearance, settings, language, minimize, quit, metric editing, ordering, deletion, and the full-dashboard action remain on top of the visual-effect view and clickable.

## Patches made since the previous QA pass

- Added a native AppKit backdrop-blur bridge dedicated to the menu-bar window.
- Switched both appearances to the translucent popover material and kept the hosting `NSWindow` non-opaque with a clear background.
- Reduced decorative tint and highlight alpha so wallpaper color can travel through the panel instead of becoming a uniform gray slab.

final result: passed

---

# Menu Bar Status Configuration Design QA

## Source and implementation

- Source visual truth: `/var/folders/6x/5n5xzp595qq6yg5b59ph39vw0000gp/T/codex-clipboard-aeb1df7c-05e1-4123-8a88-7beef2bd517b.png`.
- Dark implementation screenshot: `.build/qa/menu-status-config-dark.png`.
- Light implementation screenshot: `.build/qa/menu-status-config-light.png`.
- Full-view comparison evidence: `.build/qa/menu-status-reference-vs-implementation-20260802.png`.
- Viewport: 720 × 360 pixels at 1× for both normal and compact variants.
- State: deterministic 80% charge, 30.7°C temperature, and battery temperature selected as the second menu-bar metric.
- Focused comparison: a separate crop was not needed because the implementation screenshot is already a component-only crop and its smallest compact labels remain readable at original size.

## Findings

- P0: none.
- P1: none.
- P2: none.
- P3: the locked desktop prevented an additional live screenshot of the native menu while expanded. This does not leave an implementation gap: every native menu item uses one stable title containing the metric name and exact resulting status text, and the six-item output is covered by a semantic regression test.

## Fidelity checks

- Fonts and typography: the preview uses the existing system fonts and monospaced digits; the normal and compact variants preserve the established title and hint hierarchy with no clipping.
- Spacing and layout rhythm: the isolated capsule was replaced by a full-width menu-bar strip. The selection row remains directly below it and fits both supported densities without changing the surrounding card language.
- Colors and visual tokens: raised surface, adaptive border, primary/secondary text, and shadow all use existing app tokens and remain legible in dark and light appearances.
- Image and icon quality: all contextual and metric icons are native SF Symbols from the existing compatible icon vocabulary; no raster placeholder, custom SVG, or approximate glyph was introduced.
- Copy and content: the menu-bar strip shows the exact `80% (30.7°C)` result, while the choice shows `电池温度 · 80% (30.7°C)`. Each of the six menu items follows the same name-plus-preview rule.
- Interaction: selecting an item still calls the existing persisted setting, immediately updating the shared `MenuBarStatusLabel`; no surrounding panel controls or ordering behavior changed.

## Patches made since the previous QA pass

- Added a contextual macOS menu-bar preview using the same status-label view as the real `MenuBarExtra`.
- Added exact result previews to the collapsed selector and all six native menu item titles.
- Added a regression assertion that every metric choice contains both its localized name and its resulting menu-bar text.

final result: passed
