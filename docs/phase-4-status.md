# Phase 4 status (status tracking, list and dashboard, reminders, backup and restore)

- **As of:** 2026-10-08
- **Summary:** the invoicing loop is complete on iPhone and iPad. Payments, derived status, the filtered list,
  the Home dashboard, client balances, void, quote outcomes and local overdue reminders shipped in the first
  Phase 4 commit; backup and restore, the iPad row actions and ⌘F followed. Outstanding: the reminder check on a
  real device.

## Tasks (plan § Phase 4)

| # | Task | Status | Evidence |
|---|---|---|---|
| 1 | Record a payment (partial or full, method, reference), derived status chips | ✅ | `documents.md` §10; `GRDBPaymentService`; `PaymentEditorView`; status from `ENGINE.md` §6 (16 `status` fixtures) |
| 2 | List segments (All / Unpaid / Overdue / Paid / Drafts / Quotes), search, date filters | ✅ | `DocumentsSection` (type picker, status segments, drafts section, date-range menu, search by client or number) |
| 3 | Client detail with its documents and outstanding balance | ✅ | `ClientsSection` detail: balance per currency + document list |
| 4 | Dashboard: outstanding, overdue, paid this month (home currency, SQL `SUM`) | ✅ | `GRDBDocumentRepository.dashboard`; `HomeView` tiles |
| 5 | Void with a reason; quote accepted / declined / expired | ✅ | `documents.md` §11–12; `GRDBDocumentService.voidDocument/acceptQuote/declineQuote` |
| 6 | Reminders: business default + per-invoice override, scheduling + reconcile on launch, "Send reminder" | ✅ code · 🔲 device | `reminders.md`, 9 `reminder` fixtures, `ReminderScheduler`, `ReminderReconciler` |
| 7 | Export `.invoicebackup` via share sheet or `fileExporter` | ✅ | `backup.md` §1–2; Settings → Backup: "Save backup to Files" (`fileExporter`) and "Share backup…" (`UIActivityViewController`) |
| 8 | Restore via `fileImporter`: validate → preview counts → safety snapshot → replace all → rebuild reminders | ✅ | `backup.md` §3–4; `BackupCodec.validate` (19 `backup` fixtures); `GRDBBackupService.restore`; `RestoreConfirmationView`; the app reloads and reconciles reminders |
| 9 | "Last backup: N days ago" nudge in Settings | ✅ | `backup.md` §5; `BackupStatus.isDue` (30 days, only once something is issued); a "Due" badge on the Backup row |
| 10 | iPad: list/detail with the document preview in the detail column | ✅ | Phase 3 (`DocumentPreviewPane`) |
| 11 | iPad: row context menus (duplicate, record payment, share, void), ⌘F search | ✅ | `DocumentsRouter.open(_:then:)` + `IssuedDocumentView` runs the action; ⌘F in `InvoiceCommands` |
| 12 | iPad: drop a `.invoicebackup` onto Settings to restore | ✅ code · 🔲 device | `DroppedBackup` (`Transferable`) on Settings and on onboarding |

**Spec first:** `spec/backup.md` (new, normative), fixture kind `backup` (19 cases, checked in `make validate-spec`
by an independent JavaScript reference implementation of §3), and `domain.schema.json` now describes the seller and
buyer snapshots and the stored `ComputedDocument` (the Phase 0 sample backup predated both and was brought up to
date). ADR-0013 gained an amendment with the restore decisions.

## Definition of done

| Criterion | State |
|---|---|
| Status fixtures pass | ✅ 16/16 `status`, plus 9/9 `reminder` and 19/19 `backup` |
| A backup round trip is lossless: export → wipe → restore → same data, assets included | ✅ `BackupTests.roundTripIsLossless`: a business with a logo, deleted and live clients, an item, issued, void, converted and deleted documents, live and deleted payments; the second export equals the first and the rebuilt tax lines match |
| A restore of a corrupted file fails safely with no data change | ✅ validation rejects it before anything happens (fixtures); a file the database itself refuses mid-way rolls back (`aFailedRestoreChangesNothing` compares every table's row count and a fresh export) |
| Reminders appear after the due date on a device test | 🔲 needs a device (notifications are wired; the simulator can't wait days) |

## Found and decided during Phase 4

1. **Backups carry tombstones.** An issued invoice keeps pointing at its (possibly deleted) client, catalogue item,
   series and logo; leaving tombstones out would make many real backups unrestorable.
2. **Restore tombstones instead of deleting** and writes everything in one transaction with foreign keys checked
   at commit, so rows can arrive in any order and any failure leaves the database exactly as it was.
3. **A restore on a new phone takes over the numbering series.** Otherwise the restored business could not issue
   at all on the new device (only the owner device advances a series). Same-device restores change nothing.
4. **The free-tier counter is local** and never restored, so restoring an old backup cannot reset it.
5. **Onboarding offers "Restore from a backup"**: the common case for a backup is a new phone, which starts in
   onboarding.
6. **The sample backup was out of date** with the engine's stored result (lines lacked `rateId`/`rate`/`category`)
   and the seller snapshot (no `name`). The domain schema now pins those shapes, so the validator catches drift.

## Test counts

| Command | Tests | Where |
|---|---|---|
| `make test-core-ios` | 89 (374 fixture cases) | macOS, `swift test` |
| `make test-data-ios` | 39 (6 backup) | macOS, `swift test` |
| `make test-pdf-ios` | 10 | iOS simulator |
| `make test-ui-ios` | 56 (6 backup view model, 1 row action) | iOS simulator |
| `make test-app-ios` | 13 UI tests (backup page and onboarding restore added) | iPhone 17 Pro |

## Your next actions

1. **On a device:** issue an invoice due yesterday with a reminder on the due date and check the notification
   arrives; export a backup to iCloud Drive, delete the app, reinstall, and restore it from onboarding.
2. **iPad:** drag a `.invoicebackup` from Files onto Settings.
