# ADR-0019: Device identity survives OS backups without being cloned

- **Status:** Accepted
- **Date:** 2026-10-09
- **Amends:** `spec/setup.md` §2, ADR-0013 (OS backups stay on), ADR-0015 (device-owned series)

## Context
Numbering is safe across devices because each numbering series is owned by one device (`owner_device_id`,
`spec/sync.md` §3): only the owner allocates from it. The owner's id lives in `device_state`, which is never synced
and never written to a `.invoicebackup` file. But it is a row in the same SQLite database that the OS backs up:
iCloud device backup copies the app container, and Android Auto Backup copies the `database` domain
(`data_extraction_rules.xml`). Restoring a phone backup onto a new phone therefore clones the old phone's id. If the
old phone is still used — kept by the owner, handed to an employee — and iCloud sync is on, both phones allocate
from the same series and issue the same invoice numbers. `DuplicateNumbers` reports that afterwards; for GST,
duplicate numbers within a financial year are a compliance problem, so it must not happen in the first place.

## Options considered
1. **Exclude the database from OS backups.** Loses the user's invoices on a lost or replaced phone without iCloud
   sync (Android has none), which is the main reason OS backups stay on (ADR-0013).
2. **Use a platform identifier** (`identifierForVendor`, `ANDROID_ID`) as the device id. Their lifetimes are the
   platform's (`identifierForVendor` resets when every app of the vendor is removed; Google recommends against
   `ANDROID_ID` for app-instance identity), and they are device identifiers with privacy-label consequences, where
   a random UUID the app keeps itself is not.
3. **Keep the id in the database and a device marker outside any OS backup that moves between devices**, and give
   a copied database a new id when the two disagree.

## Decision
Option 3 (`spec/setup.md` §2):
- The marker is the device id stored where an OS backup never carries it to another device: iOS, a Keychain item
  with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` (not synchronised, never restored onto a different
  device); Android, a file in `noBackupFilesDir` (excluded from Auto Backup and device-to-device transfer).
- `DeviceIdentity.check(rowId, marker)` in the core (same name on both platforms) decides create / keep / replace;
  a marker that can't be read (a locked iPhone before first unlock, an I/O error) keeps the row and checks again
  next time, so a transient failure never changes the id.
- A replace keeps the row (device name, preferences, the free-tier mirror) and gives it a new id. The series the old
  id owned now belong to "another device", so the first issue shows the existing choice: start this device's own
  series, or take one over (`SeriesOwnership.takeOver`, which continues after the highest number issued).

## Consequences
- A new phone restored from a backup asks once, at its first issue, how to number; continuing the old phone's
  series is one tap, and if the old phone is still in use it is the one asked to choose next.
- Android reinstalls restored by Auto Backup, and builds installed before this change, also ask once (the marker did
  not exist yet). Acceptable before 1.0; there are no installed users.
- The check runs inside `DeviceStateRepository.loadOrCreate`, so every caller (launch, the reminders job, the iOS
  sync service) gets the same answer; no screen needs to know.

## Revisit when
Either platform offers a supported, per-install identifier that is excluded from backups by design, or sync on
Android lands and needs the same guarantee across more storage locations.
