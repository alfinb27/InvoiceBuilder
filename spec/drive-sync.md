# Live sync through Google Drive (v0)

Normative for sync between any mix of iPhones, iPads and Android phones through the user's own Google Drive
(ADR-0022). It reuses the Drive connection of `backup.md` §7 (same OAuth clients, same `drive.file` scope) and the
numbering rules of `sync.md` §3–5. The pure rules (§5 merge, §6 which files to read, §8 which files to delete) are
proven by `fixtures/drivesync/*.json` (kind `drivesync`).

## 1. One sync method per device

- `device_state.preferences.syncMethod`: `none` · `icloud` · `drive` (default: `icloud` on a build with iCloud
  sync and the user signed in to iCloud, otherwise `none`). Not synced, not in backups.
- Settings → Sync offers **iCloud** (Apple devices only) or **Google Drive** (any phone). Choosing one turns the other
  off on this device; local rows are kept and the newly chosen method merges with what it finds (§7).
- Android offers `none` and `drive` only. Drive sync is free, like iCloud sync.
- Turning Drive sync on also turns Drive backup on (`backup.md` §7) if it is off: one connection, one account.
- `preferences.syncEnabled` (`sync.md` §2) keeps its meaning for iCloud: it is `true` exactly when `syncMethod` is
  `icloud`.

## 2. What syncs

The records of a backup (`backup.md` §1), in its JSON encoding: `businesses`, `clients`, `catalogItems`,
`numberingSeries`, `documents` (each with its `lines`, as one record), `payments`, `assets` — tombstones included.
A document's lines travel and merge with it; a line edit always bumps the document's `updatedAt`
(`documents.md` §3). `tax_line` rows are not sent: a merged document's tax lines are rewritten from its `computed`,
exactly as a restore writes them (`backup.md` §4 step 4). `device_state` and `app_state` never sync.

## 3. The sync folder

A second visible folder, **"InvoiceBuilder sync"**, in My Drive, found or created as the backup folder is
(`backup.md` §7). Its id is remembered in `app_state` `drive_sync_folder_id`. Inside it:

| File | Written by | Content |
|---|---|---|
| `changes-<deviceId>-<seq>.json` (`seq` zero-padded to 8 digits, from 1) | that device only, never rewritten | `{ "formatVersion": 1, "deviceId", "seq", "createdAt", "data": { "<collection>": [record, …] } }` (`data` as in a backup: every collection, most of them empty) |
| `snapshot-<deviceId>.json` | that device only, updated in place | `{ "formatVersion": 1, "deviceId", "createdAt", "covers": { "<deviceId>": seq, … }, "data" }` with every record |

Every file carries `appProperties` `ibKind` (`changes` · `snapshot`), `ibDeviceId`, `ibSeq` (changes only), `ibCreatedAt`, so a
listing tells what to read without downloading. Files without `ibKind` are ignored.

## 4. Pushing local changes

- `app_state` `drive_sync_pushed_at` (epoch ms, starts at 0) and `drive_sync_next_seq` (starts at 1). The other
  keys: `drive_sync_account_email`, `drive_sync_folder_id`, `drive_sync_seen` (§6), `drive_sync_snapshot_id` and
  `drive_sync_snapshot_covers` (§8), `drive_sync_last_sync_at`, `drive_sync_last_error` (§9).
- A push collects every record with `updatedAt >= pushed_at` (tombstones included; a document when it or any of its lines changed) as of a start time `t`, writes
  them as the next `changes-…` file, then sets `pushed_at = t` and advances `next_seq`. Nothing to send → no file.
- A push runs 5 s after the last local write (debounced), when the app goes to the background, on "Sync now", and
  with the background work of `backup.md` §7.
- Records received from other devices are not echoed back on purpose; if one is sent again (its `updatedAt` is at or after
  `pushed_at`), §5 makes it a no-op everywhere.

## 5. Merging a record — `DriveSync.wins(local, incoming)`

For a record of the same collection and `id`, the incoming record replaces the local one exactly when it **wins**:

1. No local record → wins.
2. Higher `updatedAt` wins.
3. Same `updatedAt`: a tombstone (`deletedAt` set) beats a live record.
4. Still tied: the record whose **canonical text** is greater wins (UTF-8 bytes, compared byte by byte). Equal
   texts → no change. The canonical text is the record's backup JSON written with: object keys sorted by their
   UTF-8 bytes at every level; keys whose value is `null` left out; no whitespace; integers in plain decimal;
   strings escaping only `"`, `\` and U+0000–U+001F (as `\u00XX`, lowercase hex); everything else as is.

1–4 apply to every collection but `documents`, where one comparison comes first, so an issued number is never lost
(root `CLAUDE.md` rule 4): the higher `lifecycle` wins (`draft` < `issued` < `void`), whatever the timestamps. A draft
edited on one device while another issues it ends issued, without the late draft edits; a draft deleted on one device
while another issues it ends issued and live.

The rule is commutative and idempotent: any devices that have seen the same records hold the same records, whatever
order the files arrived in.

A winning record is written exactly as received (timestamps and tombstones included). A winning document replaces
its lines: lines it lists are written, its other live lines are tombstoned, and its tax lines are rewritten (§2).
Records merge in the order `businesses`, `assets`, `clients`, `catalogItems`, `numberingSeries`, `documents`,
`payments`, all in one database transaction per file. A merge never changes series ownership (unlike a restore).

## 6. Pulling — `DriveSync.toRead(entries, seen, thisDevice)`

- `app_state` `drive_sync_seen`: JSON `{ "<deviceId>": highest seq merged }`.
- From a folder listing, a pull reads either one snapshot or a run of change files:
  1. **Catching up:** if another device `d` has change files or a snapshot in the folder but not the file
     `seen[d] + 1` (§8 deleted it, or `d` has only a snapshot), read `snapshot-<d>` alone (the lowest such `d` first).
     After it merges, `seen` takes the higher of its own and the snapshot's `covers` for each device, and the pull
     lists again.
  2. **Otherwise:** every other device's change files with `seq` above `seen`, by device id then `seq`. A gap in a
     device's run (a file not yet visible) stops that device's run; the next pull continues.
- This device's own files are never read back.
- After each file merges, `seen` advances (to the snapshot's `covers`, or to the file's `seq`) in the same
  transaction, so an interrupted pull resumes cleanly.
- A pull runs when the app opens or returns to the foreground, every 60 s while it is in front, on "Sync now",
  and before every push.
- After a pull that merged anything, the steps of `sync.md` §5 run (reminders, duplicate-number check, free-tier
  check).

## 7. Connecting a device

- Settings → Sync → Google Drive (or Welcome → "I've used this app before" → "Sync with Google Drive"): sign in,
  find or create the sync folder, then a first pull (§6) with `seen = {}`, then a push of every local row
  (`pushed_at = 0`).
- A device with its own data joining a folder with data **merges** them (§5); the confirmation says so ("The
  businesses on this phone and in Google Drive will be combined"). Two businesses are never merged into one.
- Disconnecting turns sync off and forgets `drive_sync_*`; the files stay. Reconnecting starts again from
  `seen = {}` and `pushed_at = 0` (safe: §5 makes repeats no-ops).
- A different Google account than last time pauses sync with the choice of `sync.md` §2 ("Erase this device's data
  and sync with this account", with a safety snapshot first, or leave it paused). Data from two accounts is never
  merged.
- A restore (`backup.md` §4) with Drive sync on is pushed like any other edit, so it replaces data on every device,
  and the confirmation says so.

## 8. Compaction — `DriveSync.filesToDelete(entries, thisDevice, now)`

- After a push that leaves this device with more than 200 change files, it writes (or updates) its
  `snapshot-<deviceId>.json`: all rows, with `covers` = `seen` plus this device's own last `seq`.
- Then it may delete its own change files that its snapshot covers **and** that were created more than 30 days ago.
  It never deletes other devices' files or files without `ibKind`.
- A device away for longer than 30 days catches up from a snapshot (§6 step 1); its own unsent changes are still
  pushed afterwards (§4), and §5 settles any conflicts.

## 9. Status and errors

Settings → Sync shows `upToDate` (with the last sync time) · `syncing` · `paused(signedOut | accountChanged |
quotaExceeded | networkUnavailable)` · `off`, in the words of `backup.md` §7. A file that fails to parse or carries
a newer `formatVersion` stops the pull at that file and shows "Update the app to keep syncing"; nothing after it
merges.

## 10. Limits (v0)

- Conflicts resolve per record, not per column (iCloud is per column): two devices editing different fields of one
  client offline keep the later edit's whole record.
- Device clocks matter (§5 step 2). A device whose clock runs far ahead wins conflicts it should lose; the
  device-owned numbering (`sync.md` §3) keeps numbers safe regardless.
- Changes appear within about a minute while both apps are open; a closed app catches up when it opens.
