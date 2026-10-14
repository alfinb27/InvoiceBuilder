# ADR-0022: Live sync through the user's Google Drive, across iOS and Android

- **Status:** Proposed
- **Date:** 2026-10-13

## Context

iCloud sync (ADR-0015) keeps Apple devices together; Android has no sync, and an iPhone and an Android phone share
data only through a Drive backup and a full restore (ADR-0021). ADR-0021 named option 3 — live sync through the
user's Drive — as the next step once the Drive connection existed. It now does. The promises stay: no server of
ours, no account of ours, "Data Not Collected".

## Options considered

1. **Per-device append-only change files in a Drive folder**, merged record by record, last write wins (as Joplin and
   Obsidian community plugins do over Dropbox). No server; reuses the `drive.file` connection; the schema is
   already sync-safe (UUID keys, `updated_at`, tombstones, device-owned series).
2. **One shared database file in Drive** (read, merge, write back). Simple, but concurrent writers overwrite each
   other and every sync moves the whole database.
3. **A hosted backend** (Firebase, Supabase, CloudKit Web Services for Android). Real time, but accounts, running
   costs, a data-processor role; CloudKit on Android would need an Apple ID.
4. **Run iCloud and Drive sync together on Apple devices.** Keeps iCloud's per-column merge between Apple
   devices, but two engines relaying each other's edits risks echo loops and is far harder to test.

## Decision

Option 1, normative in `spec/drive-sync.md`, with **one sync method per device** (not option 4): iCloud or Google
Drive on Apple devices, Google Drive on Android. Free, like iCloud sync.

- Each device writes only its own files (`changes-<device>-<seq>.json`, never rewritten; one `snapshot-<device>.json`
  for compaction), so there are no write conflicts in Drive at all.
- Records travel in the backup encoding, so both platforms reuse their backup readers and writers.
- Merge: higher `updatedAt` wins, then tombstone, then the greater canonical text — commutative and idempotent,
  so devices converge whatever order files arrive in. A document never moves backwards in `lifecycle`.
- Numbers stay safe through the device-owned series of `sync.md` §3, unchanged.
- Pure rules (`DriveSync.wins`, `toRead`, `filesToDelete`) have `drivesync` fixtures on both platforms.
- Same names on both platforms: `DriveSync` (pure, InvoiceCore / `:core:domain`), `DriveSyncEngine` (I/O, beside
  `AutoBackupRunner`).

## Consequences

- An iPhone and an Android phone can share one business live, within about a minute while both apps are open.
- Conflicts are per record, not per column, and depend on device clocks (`drive-sync.md` §10). Acceptable for one
  person's devices; revisit if users edit the same records on two devices at once.
- Apple users who choose Drive lose iCloud's per-column merge and push-driven speed on that device.
- No schema migration: sync state lives in `app_state` and `device_state.preferences`.
- The privacy answers do not change from ADR-0021: data goes only to the user's own Drive, at their request.
- Polling (60 s in front) costs a Drive `files.list` call per minute per open device, well inside Drive quotas.

## Revisit when

- Users report lost edits from concurrent editing → per-column timestamps (a new nullable column per synced
  table, or a per-row field-clock JSON).
- Polling proves too slow or costly → the Drive `changes` API with a page token, or push notifications.
- Users want iCloud and Drive at once on Apple devices → option 4.
