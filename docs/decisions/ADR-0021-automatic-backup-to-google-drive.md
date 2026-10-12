# ADR-0021: Automatic backup to Google Drive, restore on any phone

- **Status:** Accepted
- **Date:** 2026-10-10

## Context

Backups are manual: the user exports one `.invoicebackup` file and saves it where they like (ADR-0013,
`spec/backup.md`). Nothing runs on its own, nothing remembers where the file went, and the only nudge is the 30-day
"Due" badge. Live sync is iCloud only (ADR-0015), so an iPhone and an Android phone never share data, and moving
between them means finding the last file by hand.

Users asked for backups to Google Drive "or any cloud they choose", so their invoices survive a lost phone and move
between platforms. The plan's promises still hold: no server of ours, no account needed, "Data Not Collected"
(ADR-0011, `docs/plan.md` §1).

## Options considered

1. **A remembered folder through the system picker** (iOS folder bookmark, Android SAF tree). No sign-in, any
   provider. But Google Drive can't be picked as a folder through SAF on Android, and background writes to
   third-party File Providers on iOS are unreliable: the backup would silently stop.
2. **Built-in Google Drive backup** with an optional Google sign-in and the `drive.file` scope. Reliable background
   uploads on both platforms, one-tap restore on any phone, no server. Needs a Google Cloud project and a verified
   consent screen.
3. **Live cross-platform sync through the user's Drive** (per-device change files, as Joplin does over Dropbox or
   OneDrive). The schema is ready for it (UUID keys, `updated_at` on every row, tombstones, device-owned number
   series), but it is a second sync engine on both platforms.
4. **A hosted backend** (Firebase, Supabase): real-time sync, but accounts, running costs, a data-processor role and
   the end of "No account needed".

## Decision

Option 2 now, behind a provider-neutral `CloudBackupDestination` interface (same name on both platforms), so Dropbox
or OneDrive can follow and option 3 can reuse the Drive connection later.

- **Scope:** `https://www.googleapis.com/auth/drive.file` only. Google classes it as non-sensitive (no security
  assessment); the app sees only the files it created.
- **Where:** a visible folder, "InvoiceBuilder backups", in the user's My Drive. The user can see, download or share
  the files, and restore one by hand through the file picker. Both OAuth clients (iOS, Android) belong to one Google
  Cloud project, so either app sees the other's files. If testing shows otherwise, fall back to the hidden
  `drive.appdata` folder, which one project's clients share.
- **iOS, no third-party SDK:** OAuth 2.0 for native apps with PKCE through `ASWebAuthenticationSession` (redirect on
  the reversed client ID scheme), Drive REST v3 over `URLSession`, the refresh token in the Keychain
  (`AfterFirstUnlockThisDeviceOnly`). New package `InvoiceDrive`; InvoiceCore keeps only the pure rules.
- **Android:** Google Identity's `AuthorizationClient` (`play-services-auth`, a new dependency; the app already uses
  Play services for Billing and Block Store) hands out access tokens on demand; Drive REST over
  `HttpURLConnection` (no OkHttp/Retrofit). New module `:core:drive`.
- **Gated like iCloud sync:** the feature exists only in a build that carries the OAuth client — iOS Info.plist key
  `GoogleDriveClientID` (plus its URL scheme), Android BuildConfig `GOOGLE_DRIVE_BACKUP`. Other builds show nothing.
- **Behaviour** is normative in `spec/backup.md` §7; the pure rules (when a backup is due, which file to write, which
  to prune, list order) have `autobackup` fixtures.

## Consequences

- The app now talks to Google, only after the user connects Drive and only to their account. App Store privacy
  stays "Data Not Collected" (we receive nothing); Play's Data safety form records the transfer to the user's own
  Drive at their request, encrypted in transit. The privacy policy and listings say so (`docs/product/`).
- Moving between iPhone and Android becomes: install, "I've used this app before" → "Restore from Google Drive".
- Backups in Drive are encrypted at rest by Google, not by us. Passphrase-encrypted backups are a possible follow-up.
- Setup the developer owns: the Cloud project, the Drive API, the consent screen (name, logo, privacy URL, support
  email, the `drive.file` scope), an iOS client (bundle ID) and an Android client (package + SHA-1 of the debug,
  upload and Play signing keys), and consent-screen verification before release (Testing mode allows 100 test users).

## Revisit when

- Users ask for the same business live on an iPhone and an Android phone at once → option 3 on this connection.
- Users ask for Dropbox/OneDrive → another `CloudBackupDestination`.
- Google reclassifies `drive.file`, or the one-project file visibility doesn't hold → `drive.appdata`.
