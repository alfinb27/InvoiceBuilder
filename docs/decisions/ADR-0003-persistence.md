# ADR-0003: Persistence (GRDB on iOS, Room on Android)

- **Status:** Accepted (amended by ADR-0015 for sync)
- **Date:** 2026-09-19

## Context
Financial records need explicit, testable migrations, constraints and transactional number allocation.
The Android port should reuse the same relational model.

## Options considered
iOS: SwiftData, Core Data, GRDB, SQLiteData. Android: Room, SQLDelight.

## Decision
GRDB (iOS) and Room (Android), both SQLite. `spec/schema/db/schema.sql` + numbered migrations are canonical.
CI diffs Room's exported schema JSON against the spec.

## Consequences
- Same queries, constraints and migrations on both platforms; `SUM`/`GROUP BY` available for reports.
- GRDB records are `Sendable` structs (Swift 6 friendly). One third-party dependency on iOS.
- Synced tables follow the sync-safe rules in ADR-0015 (no non-PK UNIQUE constraints).

## Revisit when
Sync needs cannot be met on GRDB (see ADR-0015 fallbacks).
