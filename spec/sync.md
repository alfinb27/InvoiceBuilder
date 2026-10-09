# iCloud sync between Apple devices (v0)

Normative for iOS/iPadOS sync (ADR-0015, `docs/plan.md` Phase 4b). Android has no sync in v1: its schema carries
the same sync-safe columns, unused. The device-owned numbering rules (§3) and the duplicate-number check (§4) are
pure functions both platforms implement (Android uses them when a restored backup brings in another device's
series); they are proven by `fixtures/series/*.json` (kind `series`).

## 1. What syncs

- **Synced tables:** `business`, `asset`, `client`, `catalog_item`, `numbering_series`, `document`, `line_item`,
  `tax_line`, `payment` — every column, tombstones included (deletes are tombstones, `setup.md` §1).
- **Never synced:** `device_state` and `app_state` (this device's id and preferences, the free-tier counter, the
  entitlement cache, `last_backup_at`).
- Conflicts resolve per column, last edit wins. Issued documents are only changed by the narrow writes of
  `documents.md` §8–12, so concurrent edits of one issued document are rare.

## 2. Sync on and off

- `device_state.preferences.syncEnabled` (bool, default `true` when the build supports sync) turns sync on for this
  device. Turning it off keeps every local row; turning it back on merges with what iCloud has.
- **Status** shown in Settings: `off` · `upToDate` · `syncing` · `paused(signedOut | accountChanged |
  quotaExceeded | networkUnavailable)` · `unavailable` (a build or device without iCloud).
- **Account change or sign-out:** sync pauses and local data stays. Settings explains why and offers "Erase this
  device's data and sync with this account" (destructive, confirmed; a safety snapshot is written first, as for a
  restore) or leaving sync paused. Data from two accounts is never merged.
- **Quota full:** a banner in Settings; local work carries on.
- **First launch:** before onboarding, a device with sync on waits up to 10 s for an initial fetch (with a
  "Skip" button). If a business arrives, it opens instead of onboarding.
- A restore (`backup.md` §4) with sync on says the data is replaced on every device signed in to the account; the
  tombstones and new rows then sync like any other edit.

## 3. Numbering on several devices

Only the owner device advances a series (`setup.md` §6, `documents.md` §6 step 4). A device that owns no live
series of a document type for the business cannot issue that type (`no_series`) until it picks one of:

### 3.1 A series of its own — `SeriesOwnership.deviceSeries`

Input: the business's live series of the type (`existing`), the config's default `pattern`, `docType`, `reset`.
Output: a new series with

- `pattern` = the default pattern with a **device letter** placed immediately before the `{seq:N}` token. The
  letter is the first of `B`…`Z` that no existing series' pattern already has immediately before its `{seq`
  token (the original series counts as `A`, whatever it has there). All 25 used → `no_device_letter`.
- `label` = the type's label plus ` (<letter>)`: "Invoices (B)", "Quotes (C)".
- `reset` = the config's, `counters = {}`, `ownerDeviceId` = this device.

`INV/{fy}/{seq:4}` with one existing series → `INV/{fy}/B{seq:4}`; with existing `…/{seq:4}` and `…/B{seq:4}` →
`INV/{fy}/C{seq:4}`.

### 3.2 Take over a series — `SeriesOwnership.takeOver`

Input: the series, this device's id, and the highest issued `sequence` per `periodKey` among live documents of that
series (any device). Output: the series with `ownerDeviceId` = this device and, for every period with issued
documents, `counters[p] = max(counters[p] ?? 1, highest[p] + 1)`. Other periods keep their counters.

The confirmation says to take over only a series the other device no longer issues from (a replaced phone). The
old owner then has no series of that type and picks again (§3.1 or §3.2) on its next issue.

## 4. The duplicate-number check — `DuplicateNumbers.find`

After each sync (and after a restore), the live issued and void documents of each business are grouped by
`(docType, number)`; every group with two or more documents is reported, numbers sorted, ids sorted within a
group. Drafts (no number) are ignored. A non-empty result shows a warning on Home ("Two invoices share the number
INV/26-27/0042") linking to the documents; nothing is renumbered automatically (issued documents are never
renumbered, root `CLAUDE.md` rule 4) — the user voids one and reissues.

By construction (§3) this list stays empty; the check exists to surface a bug or a hand-edited backup rather than
let it pass silently.

## 5. After each sync

- Reminders are reconciled for the active business (`reminders.md` §3).
- The duplicate-number check (§4) runs.
- Cached PDFs need nothing: they are keyed by the document's content (`pdf/RENDERING.md` §5).
- The cross-device free-tier check runs (`billing.md`).
