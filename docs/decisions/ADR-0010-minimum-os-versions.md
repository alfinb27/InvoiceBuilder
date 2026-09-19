# ADR-0010: Minimum OS versions

- **Status:** Accepted
- **Date:** 2026-09-19

## Decision
- **iOS/iPadOS 18.0.** Same devices as iOS 17 (XS/XR and later); adds `TabView` `.sidebarAdaptable`
  (tab bar on iPhone, sidebar on iPad) and avoids hand-written split/tab switching.
- **Android minSdk 26** (~97% of active devices; native `java.time`), **target/compile SDK 36** (Play requirement;
  edge-to-edge and large-screen adaptivity enforced).

## Revisit when
India beta testers are stuck on older versions → iOS 17 with hand-written switching (+2 days), or Android 24 with
core-library desugaring.
