# ADR-0013: Backup, restore and reminders

- **Status:** Accepted
- **Date:** 2026-09-19

## Decision
- **Backup:** OS backups stay on (iCloud device backup; Android Auto Backup via `dataExtractionRules`).
  User-facing export is one `.invoicebackup` JSON file (`spec/schema/backup.schema.json`) with images base64-encoded.
  A safety snapshot is written before any restore or migration.
- **Restore:** "replace all" after validation and a count preview. With iCloud sync on this replaces data on every
  signed-in device; the confirmation says so.
- **Reminders:** iOS pre-schedules local notifications (nearest 50 of the 64 allowed, reconciled on launch and after
  sync). Android runs a daily WorkManager job (needs `POST_NOTIFICATIONS` on Android 13+; best effort on aggressive OEMs).

## Amendment (2026-10-08, Phase 4)
Settled while specifying restore (`spec/backup.md`):
- **Backups include tombstones.** Issued documents keep referring to deleted clients, items, series and old
  images; a live-only export could not be restored without breaking or dropping those references.
- **Restore never deletes.** Rows not in the file are tombstoned in the same transaction that writes the file's
  rows (foreign keys deferred to commit), so a later iCloud sync carries the deletions and a failure leaves the
  data untouched. `tax_line` is rebuilt from each document's stored `computed`.
- **Restoring on another device takes over the numbering series** the allocator would pick, keeping their
  counters, so a phone-to-phone move keeps numbering where it left off. Phase 4b (sync) revisits this for the case
  where the other device is still issuing.
- **Local state never travels:** `device_state` and `app_state` (free-tier counter, entitlement cache,
  `last_backup_at`) are untouched by a restore, so restoring an old backup cannot reset the free-tier count.
