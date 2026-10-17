# Backup and restore (v0)

Normative for both apps' portable backup: exporting a `.invoicebackup` file, validating one, and restoring it with
"replace all" (ADR-0013, `docs/plan.md` D13). The file format is `schema/backup.schema.json`; record shapes are
`schema/domain.schema.json`. iOS implements validation in `InvoiceCore` (`BackupCodec`), export and restore in
`InvoiceData` (`GRDBBackupService`) and the screens in `InvoiceUI`; Android in `:core:domain`, `:core:data` and
`:app`. Validation is proven by `fixtures/backup/*.json` (kind `backup`); automatic backup to Google Drive (§7) by
`fixtures/autobackup/*.json` (kind `autobackup`).

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
- A file opened while the app is still starting (loading the database, or the first-launch wait for iCloud,
  `sync.md` §2) is kept, and §4 starts as soon as onboarding or the main screen shows. If several arrive, the last
  one wins. Opening a file is how a new phone usually starts, often before the app has ever finished launching.

## 7. Automatic backup to Google Drive (ADR-0021)

Only in builds that carry a Google OAuth client (iOS Info.plist `GoogleDriveClientID`, Android BuildConfig
`GOOGLE_DRIVE_BACKUP`); other builds show none of this. Calls go only to Google's OAuth and Drive v3 endpoints, over
HTTPS, and only after the user connects. The pure rules are `AutoBackupRules` (fixtures kind `autobackup`).

### 7.1 Connecting and disconnecting

- Settings → Backup shows a **Google Drive** row (On / Off / Needs attention) that opens the Google Drive page;
  **Back up to Google Drive automatically** there opens Google sign-in for the scope
  `https://www.googleapis.com/auth/drive.file` and nothing else. Cancelling changes nothing.
- Then the app finds its folder — a folder it created named **InvoiceBuilder backups**, not trashed (the earliest
  created when there are several) — or creates one in My Drive, remembers its id and backs up at once (§7.2 "Back up
  now") when there is anything to back up (a new phone that connects to restore has nothing yet).
- The Backup page shows the connected account's email. Tokens stay with the platform (iOS: Keychain, this device
  only; Android: Google Play services), never in the database or a backup.
- **Stop backing up to Google Drive** revokes the token and forgets the account and folder. Files already in Drive
  stay there.

### 7.2 When a backup runs (`AutoBackupRules.isDue`)

- `latestChangeAt` = the highest `updated_at` over the synced tables (a tombstone bumps it), or none without rows.
- Due when `latestChangeAt` exists **and** (there is no Drive backup yet **or** `latestChangeAt > lastBackupAt`)
  **and** (there was no attempt yet **or** `now − lastAttemptAt ≥ 15 minutes`).
- Checked when the app goes to the background, and by a daily background task (iOS `BGProcessingTask` needing the
  network; Android periodic WorkManager work needing a connection). The OS decides when background work really runs.
- **Back up now** runs at once, whatever the rule says. One backup at a time: a request while one runs waits for it
  and reports its result. An attempt records `drive_last_attempt_at` before it uploads. A due backup that fails is
  reported as a failure, so background work retries it (Android: WorkManager backoff from 15 minutes; not for
  `signedOut` or `quotaExceeded`, which wait for the user). No automatic attempt runs while the last error is `signedOut`.

### 7.3 Which file it writes (`AutoBackupRules.target`)

- The content is the §1 backup (the §2 export) with the §1 file name (today's local date).
- Every file carries Drive `appProperties` (strings; Drive allows 124 bytes per key plus value, so longer values are
  cut with "…"): `ibDeviceId` (this device's `device_state.id`), `ibDeviceName` (the model name the platform reports,
  e.g. "iPhone", "Pixel 8"), `ibPlatform` (`ios` | `android`), `ibCreatedAt` (the backup's `createdAt`, epoch ms),
  `ibFormatVersion`, `ibBusinesses` (live business names joined by ", "), `ibInvoices` (live issued invoices) and
  `ibClients` (live clients).
- If a file in the folder has today's file name **and** this device's `ibDeviceId`, the backup replaces that file's
  content and properties (the newest such file when there are several). Otherwise it creates a new file. Another
  device's file is never overwritten, even with the same name.
- If the remembered folder is gone or trashed, the app finds or creates it again (§7.1) and retries once.

### 7.4 Keeping the newest ten (`AutoBackupRules.filesToDelete`)

- After a successful upload, among the folder's files whose `ibDeviceId` is this device, the **10 newest** stay and the
  rest are deleted. Newer = larger `ibCreatedAt`; with equal `ibCreatedAt`, the larger file id is newer. The list to
  delete is returned oldest first.
- Files of other devices, and files without the app's properties, are never deleted.

### 7.5 Results

- Success: `drive_last_backup_at` = the backup's `createdAt`, `last_backup_at` = now (so §5's due warning clears) and
  `drive_last_error` is cleared.
- Failure: `drive_last_error` = `signedOut` (consent revoked or expired — reconnect), `quotaExceeded` (Drive is full),
  `networkUnavailable` or `other`. The Backup page shows it in plain words ("Couldn't back up to Google Drive: your
  Google Drive is full."); nothing else nags.

### 7.6 Restoring from Google Drive

- From Settings → Backup → **Restore from Google Drive…**, or Welcome → "I've used this app before" → **Restore from
  Google Drive** (which signs in first and leaves automatic backups connected on this device).
- The list shows every file in the folder that has the app's properties, **newest first**
  (`AutoBackupRules.newestFirst`, same order as §7.4): date and time, device name and platform, businesses, and the
  invoice and client counts — no download needed.
- Choosing one downloads it and starts §4 at step 1: validate, preview, safety snapshot, replace all. A file from
  either platform restores on the other.

### 7.7 Local state

`app_state` keys, local only, never synced and never in a backup; a restore leaves them as they are:
`drive_account_email`, `drive_folder_id`, `drive_last_backup_at`, `drive_last_attempt_at`, `drive_last_error`.
