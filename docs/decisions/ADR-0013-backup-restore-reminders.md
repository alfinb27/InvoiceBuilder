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
