# ADR-0015: iCloud sync (Apple devices only)

- **Status:** Proposed — to be confirmed by the Phase 0 sync spike (`docs/spikes/sync-spike.md`)
- **Date:** 2026-09-19

## Options considered
1. Point-Free SQLiteData sync engine on top of GRDB (built on Apple's CKSyncEngine).
2. Hand-written CKSyncEngine layer over GRDB.
3. SwiftData or Core Data with CloudKit.
4. Hosted backend (Firebase/Supabase).

## Decision (proposed)
Option 1, isolated in `InvoiceSync` behind a `SyncService` protocol.

## Sync-safe schema rules (both platforms)
UUID primary keys; no UNIQUE constraints except primary keys; explicit `ON DELETE`; additive-only migrations after
1.0; images as BLOB rows (synced as CKAssets); `device_state` is local and never synced.

## Numbering across devices
Each numbering series has an `owner_device_id`; only the owner advances it. Device 2 picks its own series on its
first issue (default `INV/{fy}/B{seq:4}`). "Take over series" continues from the highest synced sequence + 1.
A post-sync check flags duplicate numbers (impossible by construction). GST allows "one or multiple series"
(CGST Rule 46(b)); HMRC allows "a sequential number based on one or more series" (VAT Notice 700/21).

## Edge cases
Signed out → local-only + banner. Different Apple ID → pause and ask; never merge. Quota full → banner.
CloudKit schema must be deployed to Production before release.

## Desk spike (2026-09-19)
SQLiteData 1.12.0 resolves with GRDB 7.11.1 (+13 transitive packages, including swift-syntax) and compiles with
Xcode 27 (full Xcode is required: swift-perception uses the SwiftUI macro plugin, which Command Line Tools lack). Our schema meets SQLiteData's
documented sync rules after one change: primary keys are now `NOT NULL ON CONFLICT REPLACE`. Conflict handling is
per-column "last edit wins". Device checks: `docs/spikes/sync-spike.md`.

## Revisit when
The spike shows conflicts with our schema/triggers/migrations → hand-written CKSyncEngine (+10–15 days) or ship
sync in 1.1.
