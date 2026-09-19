# Sync spike: SQLiteData CloudKit sync on our GRDB schema

- **Date:** 2026-09-19 · **Decision:** ADR-0015 stays **Proposed** until the device run below
- **Desk result:** no blockers found; one schema change applied.

## What ran here (macOS, Command Line Tools only)

| Step | Result |
|---|---|
| Resolve GRDB + SQLiteData (`spikes/sync/Package.swift`) | ✓ SQLiteData 1.12.0, GRDB 7.11.1, plus 13 transitive packages: swift-structured-queries 0.39.2, swift-sharing 2.10.1, swift-dependencies 1.17.1, swift-perception 2.0.12, swift-syntax 604.0.0, swift-snapshot-testing 1.19.5, swift-custom-dump, swift-identified-collections, swift-issue-reporting, swift-concurrency-extras, swift-clocks, combine-schedulers, swift-collections |
| Compile | ✗ **blocked by the environment**: swift-perception needs the SwiftUI macro plugin (`SwiftUIMacros.StateMacro`), which ships with Xcode, not Command Line Tools. Re-run with Xcode. |
| Review our schema against SQLiteData's sync rules (`CloudKitSync.md` in the 1.12.0 checkout) | ✓ after one change (below) |

## SQLiteData rules vs our schema (`spec/schema/db`)

| SQLiteData rule | Our schema |
|---|---|
| Globally unique primary keys, `TEXT … NOT NULL ON CONFLICT REPLACE` | **Changed:** every table's `id` is now `TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE` (no SQL default, so the DDL stays portable to Room; ids come from the app) |
| One non-compound primary key on every synced table | ✓ |
| Foreign keys allowed; `ON DELETE` must be CASCADE, SET NULL or SET DEFAULT (RESTRICT/NO ACTION rejected when `SyncEngine` starts) | ✓ only CASCADE / SET NULL |
| No UNIQUE constraints except the primary key (validated when `SyncEngine` starts) | ✓ enforced by `make validate-spec` |
| Value-list CHECK constraints (not covered by SQLiteData's docs, found in code review) | **Changed:** removed from synced tables. A row written by a newer app version (e.g. `doc_type = 'creditNote'`, a new country) would fail to insert on a device still on an older version, and SQLite can't change a CHECK without a table rebuild. Value lists are enforced in app code; `make validate-spec` rejects them |
| Avoid CloudKit reserved names (`creationDate`, `modificationDate`, `recordID`, `recordType`, `etag`, …) | ✓ we use `created_at` / `updated_at` |
| BLOB columns sync as CKAssets; keep blobs in their own table | ✓ `asset` table |
| Migrations after release: add tables, or add columns that are nullable or have a DEFAULT with `ON CONFLICT REPLACE`; never remove or rename | Added to the repo rules (`CLAUDE.md` rule 5) |
| Conflicts: per-column "last edit wins" (not customisable) | Matches ADR-0015's assumption; payments and lines are separate rows, so concurrent edits rarely touch the same column |
| Children received before parents are cached until the parent arrives | Good for `document` → `line_item` / `tax_line` / `payment` |

## Device run still to do (needs Xcode, a paid developer account, two devices on one Apple ID)

Build a throwaway iOS app target around `spikes/sync` with `SyncEngine(for: db, tables: Business.self, Asset.self,
Client.self, CatalogItem.self, NumberingSeries.self, Document.self, LineItem.self, TaxLine.self, Payment.self)`
(`DeviceState` and `app_state` excluded), iCloud + CloudKit + push capabilities, then check:

1. `SyncEngine` starts without schema errors (validates UNIQUE/FK/PK rules).
2. A client created on device A appears on B within 30 s, and the reverse.
3. Both offline: edit different fields of one draft on each → both edits survive (per-column last edit wins).
4. Both offline: edit the *same* field → the later edit wins; document which one users see.
5. Delete a catalogue item on B → gone on A; deleting a document cascades its lines, tax lines and payments.
6. A logo (BLOB) syncs as a CKAsset and arrives intact (sha256 matches).
7. Sign out of iCloud on B → sync pauses and local data stays; sign in with a different Apple ID → no merge.
8. Add a nullable column in a second migration on A only → B (old schema) keeps syncing; after updating B, data appears.
9. Measure the first full sync of 1,000 documents (time and CloudKit request count).

Record results here and flip ADR-0015 to Accepted (or apply its fallbacks).
