# Feature parity (v1)

The scope contract for v1: a row is done when both columns are ticked. Update this file in the same change as the
feature. Status legend: ☐ not started · ◐ in progress · ☑ done · — not applicable.

| Area | Feature | Spec | iOS/iPadOS | Android |
|---|---|---|---|---|
| Core | All `spec/fixtures` pass (count = `make validate-spec` total, 374 at spec v0.5) | ☑ | ☑ 374/374 | ☐ |
| Core | Tax engine (IN, GB, GENERIC) | ☑ v0 (`ENGINE.md`, 105 `tax` fixtures, review pending) | ☑ (93.7% region coverage) | ☐ |
| Core | Numbering, status, formatting, amount in words, tax ID validation, UPI links | ☑ v0 | ☑ | ☐ |
| Core | Draft defaults and catalogue prices on documents (`document` fixtures) | ☑ `documents.md` §2–3 | ☑ | ☐ |
| Data | SQLite schema + migrations (GRDB / Room) | ☑ v0 (3 migrations) | ☑ migrations run the spec SQL; tested equal to `schema.sql` (incl. 0003, `MigrationTests`) | ☐ |
| Setup | Onboarding (country, registration, business, tax ID, bank/UPI, logo, signature) | ☑ `setup.md` §3 | ☑ | ☐ |
| Setup | Clients (B2B/B2C, addresses, tax ID) | ☑ `setup.md` §5 | ☑ | ☐ |
| Setup | Settings: business profile, invoice defaults, numbering series, custom rates (GENERIC), logo and signature | ☑ `setup.md` §4, 6, 7, 9 | ☑ | ☐ |
| Setup | Field rules and typed amounts (`field`, `input` fixtures) | ☑ `setup.md` §8, 11 | ☑ | ☐ |
| Setup | Item catalogue (unit, price, rate, HSN/SAC, inclusive flag) | ☑ `setup.md` §10 | ☑ | ☐ |
| Documents | Invoice builder (lines, discounts, shipping, currency, supply type, reverse charge), autosaved drafts | ☑ `documents.md` §2–5 | ☑ | ☐ |
| Documents | Quotes + convert to invoice; duplicate; accept/decline | ☑ `documents.md` §7, §12 | ☑ convert/duplicate; accept/decline via the Actions menu ("Mark accepted"/"Mark declined") | ☐ |
| Documents | Issue (number allocation, snapshots, free counter) + void | ☑ `documents.md` §6, §11 | ☑ issue; void via the Actions menu (reason alert), reason/voided-at shown on a voided document | ☐ |
| PDF | 4 templates, preview, share (WhatsApp), print, save | ☑ `pdf/RENDERING.md`, `pdf/layout/*.json`, 9 `pdf` fixtures | ☑ `InvoicePDF` + preview screen, share sheet, AirPrint, Save to Files | ☐ |
| PDF | UPI QR, amount in words, signature | ☑ `RENDERING.md` §1.3 | ☑ CIQRCodeGenerator; words from the engine; signature image or a line to sign | ☐ |
| Tracking | Payments, derived status, list + dashboard, search | ☑ `documents.md` §10; status already `ENGINE.md` §6 | ☑ data layer; Invoices list status segments (All/Unpaid/Overdue/Paid) + date-range filter + search; Home dashboard tiles (home currency only); client detail outstanding balance + document list; "Record payment" sheet + a read-only, swipe-to-delete Payments section on the issued document | ☐ |
| Tracking | Overdue reminders (local notifications / WorkManager) | ☑ `reminders.md`, 12 `reminder` fixtures (dates before `from` dropped before the cap) | ☑ `ReminderScheduler` (core, fixture-proven); `NotificationScheduling`-backed local notifications from today on, showing the outstanding amount; reconciled on launch, after issuing an invoice, after a payment recorded/removed, after a void, after the business default changes; per-invoice override in the builder; "Send reminder" share action (seller name and UPI ID from the issued document's snapshot) | ☐ |
| Data safety | Backup export + restore (cross-platform file) | ☑ `backup.md`, 19 `backup` fixtures, `samples/` | ☑ `BackupCodec` (fixture-proven), `GRDBBackupService` (lossless round trip, one-transaction restore with tombstones, safety snapshots, series takeover); Settings → Backup (Save to Files, Share, restore with a count preview, "Last backup" + due badge); restore from onboarding; open `.invoicebackup` from Files/Mail; drop onto Settings on iPad | ☐ |
| Sync | iCloud sync between Apple devices | ☐ | ☐ | — |
| Billing | Free tier (15), paywall, purchase, restore/refresh, refunds | ☑ v0 | ☐ | ☐ |
| Adaptive UI | iPad split view + two-pane builder / tablet + foldable panes | — | ◐ adaptive shell, split views, two-pane builder (live PDF preview or totals, from 700 pt), popover line editor, drag the PDF out, row context menus (duplicate, share, record payment, void, delete), ⌘N/⇧⌘N/⌘↩/⌘D/⌘P/⌘F | ☐ |
| Quality | Accessibility (Dynamic Type/font scale, VoiceOver/TalkBack) | — | ◐ labels on every setup control, system text styles; device audit in Phase 6 | ☐ |
