# ADR-0001: Build order and code sharing

- **Status:** Accepted
- **Date:** 2026-09-19

## Context
Solo developer, expert in Swift, new to Android. Targets India (~95% Android) and the UK (~50/50). Tax behaviour
must be identical on both platforms.

## Options considered
1. Two native apps implementing a shared spec, proven equal by golden fixtures.
2. Kotlin Multiplatform core (tax engine, models) with native SwiftUI/Compose UIs.
3. One cross-platform UI (Compose Multiplatform, Flutter, React Native).
4. Android first.

## Decision
Option 1, iOS first: launch on iOS (UK + India), then port to Android (Phase 7).

## Consequences
- Business logic is written twice (~1.5–2.5k lines each) but is small because tax rules are JSON data.
- `spec/fixtures` is the contract; CI runs it on both platforms.
- Android benefits from real user feedback and a spec corrected during the iOS beta.

## Revisit when
Shared logic grows substantially (sync conflict rules, reports, recurring schedules) or a third client appears
→ move the core to KMP; fixtures carry over unchanged. Or Android traction in India clearly outpaces iOS.
