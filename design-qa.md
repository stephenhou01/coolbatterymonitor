# Menu Bar Status Design QA

## Scope

- Reference: text-only menu-bar status `60% (4h 06m)` with no battery or charging glyph.
- Implementation: `MenuBarStatusLabel` plus the shared top-status configuration used by the popover and Settings page.
- Production SwiftUI components were rendered from the signed fixed-path QA app in `.build/qa/MenuStatusRenderer/`.

## Evidence

- Side-by-side status comparison: `.build/qa/menu-status-reference-comparison.png`
- Light configuration: `.build/qa/menu-status-config-light.png`
- Dark configuration: `.build/qa/menu-status-config-dark.png`

## Findings

- P0: none.
- P1: none.
- P2: none.
- P3: the final menu-bar font size and vertical centering remain controlled by macOS `MenuBarExtra`, as expected.

## Verification

- The status output contains only percentage and the configured secondary metric.
- Charging, AC-connected, and battery-powered states share the same text-only presentation.
- The percentage remains fixed; runtime, power, temperature, cycles, health, and current are selectable and persisted.
- The configuration is directly accessible in both the popover and the full Settings page.
- Light and dark configuration surfaces remain readable and use the existing glass/semantic-color design system.

final result: passed
