# Phase 7 status (Android: core port, app, billing, release readiness)

- **As of:** 2026-10-09
- **Summary:** the Android app is at feature parity with iOS 1.0 in code: `:core:domain` passes all 410 fixtures, the
  data layer runs the spec's SQL and restores iOS backups, the PDF renderer draws the same four templates (Hindi
  included), and every screen is ported — onboarding, Home, Invoices/Quotes with the two-pane builder, Clients, Items,
  Settings, backup, reminders and the paywall. It runs on an API 36 emulator, the R8 release build runs, and CI covers
  JVM tests, Lint, the release build and the device tests. What is left needs the Play Console account, real devices
  and testers.

## 7a — project, core, data, setup screens

| Task | Status | Evidence / what is left |
|---|---|---|
| Project (Gradle KTS, version catalog, debug suffix, CI on Ubuntu) | ✅ | `android/`, `.github/workflows/android.yml` (`test` + `device` jobs) |
| `:core:domain` at fixture parity | ✅ | 413 JVM tests, 410/410 fixtures (`make test-core-android`) |
| `:core:data` (Room over the spec SQL, repositories) | ✅ | `DataTests` (schema equals `schema.sql`, repositories, backups incl. iOS files) |
| Setup screens, adaptive shell, signature pad, photo picker | ✅ | onboarding, Clients, Items, Settings; `NavigationSuiteScaffold`; Compose canvas signature → PNG |
| Survives rotation, dark mode, "Don't keep activities" without data loss | ✅ | state lives in the activity-scoped `AppModel` (ADR-0018); drafts autosave and flush on `ON_STOP`; `RouterState` (`SavedStateHandle`) reopens the tab and open document after a real process death (checked with `am kill` on the emulator) |
| Offline launch | ✅ | found on the emulator without Play: billing's reconnection held the launch spinner 10+ s. Launch no longer waits for the store (state stays `unknown`, issuing below the limit still works) and the billing connection gives up after 5 s. Cold launch 1.3 s |
| First internal-track upload | 🔲 account | needs the Play Console app and an upload key |

## 7b — builder, PDF, lifecycle features

| Task | Status | Evidence / what is left |
|---|---|---|
| Builder (autosave, line editor, pickers, discounts, currency, tax options) | ✅ | `DocumentViewModel` (same intents as iOS); UI test issues INV/26-27/0001 for ₹7,080.00 |
| PDF (`:core:pdf`, same templates) + preview, share, print | ✅ | 10 device tests with PDFBox text extraction (pagination, closing blocks, Devanagari, watermark, images, Letter, timing); `make pdf-samples-android` |
| UPI QR (ZXing) | ✅ | error correction M, drawn only in the drawing pass |
| Payments, list, dashboard, search, filters | ✅ | |
| Reminders (daily WorkManager job, channel, permission at first issue) | ✅ | ADR-0013 / ADR-0018 |
| Backup (SAF save/open, share, restore preview, open from other apps), Auto Backup rules | ✅ | iOS → Android restore covered by `DataTests`; 🔲 a manual round trip with a file from an iPhone |
| Screenshot tests (Roborazzi) | ⏭ | not added; the device UI tests and the PDF samples cover the drawing. Add with the store screenshots |
| Large screens (two-pane builder ≥ 700 dp, list/detail ≥ 600 dp, Ctrl+N) | ✅ / 🔲 | checked on the emulator resized to an unfolded foldable (2208×1840: rail + list + builder) and a 10" landscape tablet (rail + list + builder + live PDF preview); the open draft survived both resizes. 🔲 a real foldable fold/unfold and freeform windows |
| Monkey test (no ANRs) | ✅ | 10,000 events (seeds 7, 99): no crash, no ANR. One earlier run flagged "no focused window" while the monkey had another app's screen open; the main thread was idle |
| Generation ≤ 2 s on a low-end device | ◐ | 60 lines render in well under 1 s on the emulator (test bound 3 s); 🔲 a real low-end phone |

## 7c — billing, release

| Task | Status | Evidence / what is left |
|---|---|---|
| `:core:billing` (Play Billing 9: pending, acknowledge, startup sweep, refresh on resume) | ✅ code | `StoreEntitlementServiceTests` (10, same cases as iOS) |
| Block Store counter mirror | ✅ code | best effort, `setShouldBackupToCloud(true)` |
| License-tester matrix (buy, cancel, pending → complete, refund, reinstall) | 🔲 account | needs the `<applicationId>.unlimited_invoices` product in Play Console |
| R8 with keep rules for kotlinx.serialization | ✅ | release APK 3.9 MB, runs the seeded and demo businesses on the emulator |
| Mapping file upload, Baseline Profile | 🔲 | mapping uploads with the first bundle; Baseline Profile after a device is available to record it |
| Signing (Play App Signing + upload key) | 🔲 account | `docs/product/play-release.md` |
| Play Console forms, listing, screenshots, tracks | 🔲 account | `docs/product/play-release.md` |

## Your next actions (in order)

1. Pick the final application ID together with the iOS bundle ID (`docs/product/naming.md`); it is
   `app.invoicebuilder.invoices` in code today and the billing product ID follows it.
2. Create the Play Console app, an upload keystore (back it up), and the in-app product; upload an internal build.
3. Start the closed test early (≥ 12 testers for 14 days on a personal account).
4. Run the license-tester matrix and a real low-end phone pass (PDF time, TalkBack, a 30-minute monkey run).
