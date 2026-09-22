# ADR-0016: Foldable iPhone (Duo) support

- **Status:** Accepted
- **Date:** 2026-09-22

## Decision
Adopt iOS 27.1's hinge and arrangement APIs (`DeviceHinge` / `.onHingeChange` and `.reservedRegions(kind:)` in
SwiftUI; `UIHingeInteraction` / `UIArrangementViewController` at the UIKit layer they're built on) as an
**additive** layer behind `if #available(iOS 27.1, *)`. The app's minimum deployment target stays iOS 18
(ADR-0010, unchanged) — every device below 27.1 keeps exactly today's compact/regular, width-driven adaptive
layout as the fallback.

First (and for now, only) screen: the invoice/quote builder (`DocumentBuilderView`). It already splits into a
form pane + a preview/totals pane at `width >= 700 && sizeClass == .regular` (ADR-0014); that condition already
covers the unfolded inner display in landscape, since a wide regular-width window is exactly what that check
was written for. What's new:
- Hinge `.partiallyOpen` (half-open/tabletop posture — the closest Apple equivalent to what other platforms call
  "flex mode"; Apple does not use that term) switches the builder to a vertical split aligned to the physical
  hinge via `reservedRegions(kind: .division)`: preview/totals above the crease, the form below it. The existing
  side-by-side `HStack` split is unusable here since nothing should be drawn across the fold.
- Hinge `.fullyOpen` leaves the existing width/size-class-driven two-pane layout as-is.
- No `ArrangementView` adoption yet — the current `HStack`-based split already satisfies the fully-open case, and
  introducing `ArrangementView` (which requires 27.1) would mean maintaining two parallel layout containers for a
  screen where the width-driven one already works. Revisit once a second screen needs it.

Android has no foldable work planned before Phase 7 (ADR-0014); this ADR doesn't touch `android/`.

## Consequences
- No behavior change for any device below iOS 27.1.
- Untested claim to verify on-device/on-simulator: that the unfolded inner display actually reports
  `horizontalSizeClass == .regular` in landscape the way an iPad does. The `.partiallyOpen` path is
  hinge-status-driven and doesn't depend on that assumption; the `.fullyOpen` path does.

## Revisit when
A second screen needs hinge-aware layout (adopt `ArrangementView` at that point instead of hand-rolling more
`HStack`/`reservedRegions` combinations), or Phase 7 Android foldable work needs the equivalent behavior.
