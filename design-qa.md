# Compact Main Window Design QA

## Source and implementation

- Source visual truth: `/var/folders/6x/5n5xzp595qq6yg5b59ph39vw0000gp/T/codex-clipboard-be483634-4aa0-44cd-93e2-5988537ff504.png`
- Default-size implementation: `.build/qa/compact-main-window-light.png`
- Minimum-size implementation: `.build/qa/compact-main-window-minimum-light.png`
- Full-view comparison: `.build/qa/compact-window-reference-comparison.png`
- Reference viewport: 2524 × 1820 pixels, light appearance, Overview, AC connected.
- Implementation viewport: 1040 × 680 points (2080 × 1360 Retina pixels), light appearance, Overview, AC connected.

## Findings

- P0: none.
- P1: none.
- P2: none.
- P3: the interactive desktop was locked, so the final system traffic-light chrome was not recaptured. The comparison uses the signed production SwiftUI content at the exact configured content size; macOS continues to provide the unchanged native window chrome.

## Fidelity checks

- Typography: hierarchy and optical weights are unchanged. The main runtime value now stays on one line and scales down at the 800-point minimum width.
- Spacing and layout: the default frame changed from 1240 × 860 to 1040 × 680, reducing occupied area by about 34%. The sidebar changed from 218 to 196 points, leaving more width for the dashboard without changing navigation structure.
- Colors and tokens: no palette, material, border, shadow, or semantic-state token changed.
- Image and icon quality: the existing SF Symbols and custom metric-icon system are unchanged and remain sharp at both tested sizes.
- Copy and content: no user-facing information was removed, abbreviated, or reordered. Smaller windows scroll vertically as before.

## Patches made

- Added a one-time window-size migration that shrinks an oversized restored window and centers it, while preserving later user resizing.
- Lowered the resizable minimum to 800 × 560 and verified the Overview at that exact size.
- Kept manual enlargement available; the change only corrects the initial and legacy oversized frame.
- Added a one-line safeguard for long runtime values at the minimum width.
- The signed Universal Release app launched at 1020 × 666 on this Mac because its existing restored frame was already smaller than the new 1040 × 680 default; it was intentionally not enlarged.

final result: passed
