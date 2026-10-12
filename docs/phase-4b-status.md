# Phase 4b status (iCloud sync between iPhone and iPad)

- **As of:** 2026-10-08
- **Summary:** the sync layer, device-owned numbering and every screen that depends on them are built and tested
  against SQLiteData's CloudKit mock. Building it found a real blocker the desk spike could not see (a reference
  cycle in the schema), now fixed with migration 0004. What remains needs the Apple developer account: the iCloud
  capability, the container, and the two-device script of `docs/spikes/sync-spike.md`.

## Tasks (plan § Phase 4b)

| # | Task | Status | Evidence |
|---|---|---|---|
| 1 | `InvoiceSync`: `SyncEngine` over all business tables (`DeviceState` excluded), behind `SyncService` | ✅ | `LiveSyncService`; `SyncedTables.swift` (9 tables, generated from `schema.sql`); `InvoiceSyncTests`: mirrors equal the schema, the engine starts on it |
| 2 | Capabilities: iCloud/CloudKit container, push, background remote notifications | 🔲 account | needs the developer team; then set `InvoiceSyncContainer` in `App-Info.plist` (see below) |
| 3 | Numbering: own series with a device letter, series picker on the first issue, "take over", duplicate check | ✅ | `sync.md` §3–4; 11 `series` fixtures; `GRDBNumberingService`; `SeriesChoiceSheet`; Home warning |
| 4 | First launch: iCloud check before onboarding (10 s, Skip) | ✅ | `AppModel.waitForICloud`; tests for both outcomes |
| 5 | Hidden duplicate-business picker | ✅ already | `setup.md` §2: the active business falls back to the earliest; a picker appears with two or more live businesses (Phase 1) |
| 6 | Settings: status row and on/off toggle that keeps local data | ✅ | Settings → iCloud sync (`SyncPage`) |
| 7 | Account change pauses and asks; quota banner | ✅ code · 🔲 device | `AccountDelegate` keeps data (SQLiteData would erase it); "Erase this device's data and sync with this account" after a safety snapshot |
| 8 | Restore-with-sync semantics | ✅ | the restore confirmation says every device is replaced when sync is on |
| 9 | Reconcilers after sync: reminders, PDF cache, free-limit check | ✅ reminders · ✅ PDF (content-keyed, nothing to do) · Phase 5 free limit | `observeRemoteChanges` → `reconcileReminders` |
| 10 | Tests: series ownership, duplicate check, a `SyncService` fake in the view-model tests | ✅ | `NumberingServiceTests` (3), `SyncTests` (6, with `FakeSyncService`) |

## Definition of done (two-device script, §11 of the plan)

All of it needs two devices on one Apple ID and a signed build, so none of it can be ticked yet:
edits reach the other device in under 30 s; concurrent offline edits merge; deletes propagate; two devices issuing
offline never share a number (true by construction, §3); switching Apple ID pauses sync; a restore warns, then
propagates; no sync work on the main thread (the engine runs on its own; the status poller only reads flags).

## Found and decided

1. **`SyncEngine` rejects reference cycles**, a self-reference included, and `document.converted_from_id`
   referenced `document`. Migration 0004 rebuilds the table without that foreign key; the column and values stay.
   `make validate-spec` now fails on any cycle. Before 1.0 a rebuild is acceptable; after it, rule 5 forbids it.
2. **Account changes never erase silently.** SQLiteData's default on sign-out or an account switch is to delete
   local data; our delegate pauses instead, and erasing is an explicit choice with a snapshot first.
3. **Sync is switched by the build**, not by a flag in code: without `InvoiceSyncContainer` in the Info.plist the
   app behaves exactly as before (`unavailable`), so simulator builds, UI tests and builds without the capability
   cannot crash on a missing entitlement.
4. **SQLiteData's macros** need `-skipMacroValidation` on the command line (Makefile) and a one-time trust in Xcode.

## Turning sync on (once the developer account exists)

1. In Xcode, InvoiceApp target → Signing & Capabilities: add **iCloud** (CloudKit, container
   `iCloud.<bundle id>`), **Push Notifications** and **Background Modes → Remote notifications**.
2. Add `InvoiceSyncContainer` = `iCloud.<bundle id>` to `ios/App-Info.plist`.
3. Run the device script in `docs/spikes/sync-spike.md` and record the results there; deploy the CloudKit schema to
   Production before the App Store release.

## Test counts

| Command | Tests |
|---|---|
| `make test-core-ios` | 89 suites' tests, 385 fixture cases |
| `make test-data-ios` | 43 |
| `make test-sync-ios` (new) | 2 |
| `make test-ui-ios` | 62 |
