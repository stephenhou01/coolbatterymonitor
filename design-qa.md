# Runtime Help Drawer Design QA

## Source and implementation

- Source visual truth: `/var/folders/6x/5n5xzp595qq6yg5b59ph39vw0000gp/T/codex-clipboard-4c59ecfb-87a3-462a-84fa-1bdbdca80ca5.png`
- Implementation screenshot: `.build/qa/runtime-help/runtime-help-dark.png`
- Full-view and focused comparison: `.build/qa/runtime-help/runtime-help-comparison.png`
- Viewport: source 910 × 1262 pixels; implementation 1080 × 800 points rendered at 2048 × 1434 pixels, dark appearance, runtime help open.
- State: deterministic Mac16,12 fixture with a valid 135-minute macOS reading, five recent power samples, and a current 16.68 W load.

## Findings

- P0: none.
- P1: none.
- P2: none.
- P3: none. The source showed one derived result; the implementation intentionally extends the same drawer pattern to the user-requested primary system value plus two derived comparisons.

## Fidelity checks

- Typography: keeps the rounded title hierarchy, monospaced numeric values, small monospaced field labels, and readable optical weight from the source. The primary system time is visibly dominant.
- Spacing and layout: preserves the 470-point drawer, section rhythm, header divider, card radius, and scroll behavior. The two derived cards share one row below the full-width system result without clipping.
- Colors and tokens: retains the existing glass-dark surface and cyan primary accent; purple and yellow distinguish the two calculated values without changing the product palette.
- Image and icon quality: this drawer contains no raster assets or custom decorative artwork. Existing native controls and SF Symbols remain unchanged and sharp.
- Copy and content: clearly separates the macOS direct value, ten-minute median-power estimate, and current-load estimate. All three show their inputs and formulas further down the same drawer.

## Patches made since the previous QA pass

- Replaced the single runtime result block with one primary system card and two derived comparison cards.
- Added a ten-minute median-power calculation with a minimum of five valid samples, plus a 120-second freshness limit for the current-load estimate.
- Added raw fields, formulas, substituted values, and trust-boundary copy for all three time values.
- Added native copy for all ten supported languages and deterministic runtime-help snapshot coverage.

final result: passed
