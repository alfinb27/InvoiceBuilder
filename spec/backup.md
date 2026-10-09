# Backup and restore (v0)

Normative for both apps' portable backup: exporting a `.invoicebackup` file, validating one, and restoring it with
"replace all" (ADR-0013, `docs/plan.md` D13). The file format is `schema/backup.schema.json`; record shapes are
`schema/domain.schema.json`. iOS implements validation in `InvoiceCore` (`BackupCodec`), export and restore in
`InvoiceData` (`GRDBBackupService`) and the screens in `InvoiceUI`; Android in `:core:domain`, `:core:data` and
`:app`. Validation is proven by `fixtures/backup/*.json` (kind `backup`).

## 1. What a backup holds

- Every row of the synced tables — `business`, `client`, `catalog_item`, `numbering_series`, `document` (with its
  live `line_item` rows as `lines`, in position order), `payment`, `asset` — **tombstoned rows included**. Issued
  documents keep pointing at deleted clients, items, series and old images, so a backup without tombstones could not
  be restored without breaking those references (or losing them).
- Not included: `tax_line` (derived: restore rebuilds it from each document's stored `computed`), tombstoned lines,
  and the local tables `device_state` and `app_state` (this device's id, preferences, the free-tier counter, the
  entitlement cache and `last_backup_at` never travel).
- Each collection is sorted by `createdAt`, then `id`, so the same data always gives the same file.
- `counts` are the array lengths (tombstones included). `dbSchemaVersion` is the highest migration applied.
  `createdAt` is the export time (epoch ms UTC); `app` is the writing platform and its version.
- Images are `dataBase64` with their lowercase hex `sha256`.
- File name: `InvoiceBackup-YYYY-MM-DD.invoicebackup` (today's local date). The content is UTF-8 JSON.

## 2. Exporting

- Reads one consistent snapshot of the database (one read transaction), then writes the file.
- After the user has saved or shared the file, `app_state.last_backup_at` = now (epoch ms). Cancelling the save
  sheet does not count.
- Exporting is never locked by the free tier (`billing.md`).

## 3. Validating a file (`BackupCodec.validate`)

A pure function of the file bytes and this app's schema version. The first failing check wins, in this order:

| # | Check | Error code |
|---|---|---|
| 1 | The bytes are a JSON object | `not_json` |
| 2 | `format` is `"invoicebuilder-backup"` | `not_a_backup` |
| 3 | `formatVersion` is a supported version (v0 reads `1`) | `newer_format` when higher, `not_a_backup` when missing or lower |
| 4 | `dbSchemaVersion` ≤ this app's schema version | `newer_schema` (a newer app wrote it; restoring could drop fields) |
| 5 | Every record decodes as its domain type (`schema/domain.schema.json`); unknown keys are ignored | `invalid_record` |
| 6 | `counts.<collection>` equals the length of `data.<collection>`, for all seven | `count_mismatch` |
| 7 | Ids are unique within each collection (lines: within their document) | `duplicate_id` |
| 8 | Every asset's `dataBase64` decodes and its SHA-256 equals `sha256` | `asset_hash_mismatch` |
| 9 | References resolve inside the file (below) | `dangling_reference` |

References (a `null` is always fine): every `businessId` → `businesses`; `business.logoAssetId` /
`signatureAssetId` → `assets`; `document.clientId` → `clients`; `document.seriesId` → `numberingSeries`;
`document.convertedFromId` → `documents`; `line.catalogItemId` → `catalogItems`; `payment.documentId` → `documents`.

On success the result is a **preview**: the decoded file plus `live`, the per-collection count of rows whose
`deletedAt` is `null` (the numbers shown to the user before restoring).

Older files are accepted: `formatVersion` 1 and any `dbSchemaVersion` from 1 up to this app's. Fields a record
lacks take their domain defaults (the same defaults the migrations give old rows).

## 4. Restoring ("replace all")

1. Validate (§3). A failure changes nothing and shows the error.
2. Show the preview (§3 `live` counts, the backup's `createdAt` and platform) and ask to confirm. The confirmation
   says that the current data on this device is replaced; with iCloud sync on (Phase 4b) it says the data is
   replaced on every device signed in to the same iCloud account.
3. **Safety snapshot:** export the current data (§1) to the app's private `Snapshots/` folder as
   `pre-restore-<epoch ms>.invoicebackup`, keeping the newest 3. If the snapshot cannot be written, stop: nothing
   changes.
4. In **one write transaction** (foreign keys are checked at commit):
   - every synced row whose id is in the backup is written exactly as the backup has it (timestamps and tombstones
     included; an existing row with that id is replaced);
   - every other live row of the synced tables is tombstoned (`deleted_at` = `updated_at` = now) — never deleted
     with SQL `DELETE`, so sync can carry the deletion;
   - each restored document's lines are written from `lines` (`created_at` = `updated_at` = the document's
     `updatedAt`); its other live lines are tombstoned;
   - each restored document's live `tax_line` rows are tombstoned, and for a document with a stored `computed`
     one new `tax_line` row is written per `computed.taxLines` entry (new ids);
   - **series ownership:** for each restored, live business and each document type, if this device owns no live
     series of that type, it takes over the series the allocator would otherwise pick (`documents.md` §6: earliest
     `createdAt`, then lowest `id`, among the live series of that type) by setting `ownerDeviceId` to this device.
     Its counters are kept, so numbering continues after the highest number in the backup.
   Any failure rolls the whole transaction back: the data is exactly as before.
5. Afterwards: the active business is re-chosen (`setup.md` §2 — the preference stays if it still names a live
   business), local reminders are rebuilt for it (`reminders.md` §3), and cached PDFs are dropped.
6. `app_state` is untouched: the free-tier counter never goes down by restoring an older backup, and
   `last_backup_at` stays as it was.

**Lossless round trip:** export on a device, wipe, restore on the same device, export again: the two files' `data`
are identical (only `createdAt` differs).

## 5. "Last backup" in Settings

- The Backup page shows "Last backup: today / yesterday / N days ago" from `app_state.last_backup_at`, or "Never
  backed up".
- A backup is **due** when at least one document has been issued and the last backup is missing or 30 or more days
  old. A due backup shows a warning on the Backup row and page. Nothing else nags.

## 6. Opening a backup from outside the app

- The app declares the `.invoicebackup` type (`com.invoicebuilder.backup`, conforming to JSON). Opening such a file
  in the app (Files, Mail, AirDrop), or dropping one onto Settings on iPad, starts §4 at step 1.
