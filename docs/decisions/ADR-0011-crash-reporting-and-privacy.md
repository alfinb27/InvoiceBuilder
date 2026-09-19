# ADR-0011: Crash reporting, analytics and privacy

- **Status:** Accepted
- **Date:** 2026-09-19

## Decision
First-party diagnostics only in v1: Xcode Organizer + MetricKit (iOS), Play Console Android vitals (Android),
plus TestFlight / internal-track feedback. No third-party analytics or crash SDKs. Target privacy labels:
App Store "Data Not Collected" (subject to the iCloud wording check in Phase 6); minimal Play Data safety form.

## Revisit when
Beta crashes cannot be reproduced from first-party data → add Sentry at the Phase 6 gate and update labels.
