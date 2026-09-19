# Feature parity (v1)

The scope contract for v1: a row is done when both columns are ticked. Update this file in the same change as the
feature. Status legend: ☐ not started · ◐ in progress · ☑ done · — not applicable.

| Area | Feature | Spec | iOS/iPadOS | Android |
|---|---|---|---|---|
| Core | All `spec/fixtures` pass (count = `make validate-spec` total, 254 at spec v0.1) | ☑ | ◐ 127/254 (validation, field, input, format, numbering; tax, rounding, distribute, words, status, UPI in 2a) | ☐ |
| Core | Tax engine (IN, GB, GENERIC) | ☑ v0 | ☐ | ☐ |
| Core | Numbering, status, formatting, amount in words, tax ID validation | ☑ v0 | ◐ tax IDs, number patterns, money/percent/quantity formatting; status and words in 2a | ☐ |
| Data | SQLite schema + migrations (GRDB / Room) | ☑ v0 | ☑ migrations run the spec SQL; tested equal to `schema.sql` | ☐ |
| Setup | Onboarding (country, registration, business, tax ID, bank/UPI, logo, signature) | ☑ `setup.md` §3 | ☑ | ☐ |
| Setup | Clients (B2B/B2C, addresses, tax ID) | ☑ `setup.md` §5 | ☑ | ☐ |
| Setup | Settings: business profile, invoice defaults, numbering series, custom rates (GENERIC), logo and signature | ☑ `setup.md` §4, 6, 7, 9 | ☑ | ☐ |
| Setup | Field rules and typed amounts (`field`, `input` fixtures) | ☑ `setup.md` §8, 11 | ☑ | ☐ |
| Setup | Item catalogue (unit, price, rate, HSN/SAC, inclusive flag) | ☑ `setup.md` §10 | ☑ | ☐ |
| Documents | Invoice builder (lines, discounts, shipping, currency, supply type, reverse charge) | ☐ | ☐ | ☐ |
| Documents | Quotes + convert to invoice | ☐ | ☐ | ☐ |
| Documents | Issue (number allocation, snapshots, free counter) + void | ☐ | ☐ | ☐ |
| PDF | 4 templates, preview, share (WhatsApp), print, save | ☐ | ☐ | ☐ |
| PDF | UPI QR, amount in words, signature | ☐ | ☐ | ☐ |
| Tracking | Payments, derived status, list + dashboard, search | ☐ | ☐ | ☐ |
| Tracking | Overdue reminders (local notifications / WorkManager) | ☐ | ☐ | ☐ |
| Data safety | Backup export + restore (cross-platform file) | ☑ v0 | ☐ | ☐ |
| Sync | iCloud sync between Apple devices | ☐ | ☐ | — |
| Billing | Free tier (15), paywall, purchase, restore/refresh, refunds | ☑ v0 | ☐ | ☐ |
| Adaptive UI | iPad split view + two-pane builder / tablet + foldable panes | — | ◐ adaptive shell, split views, step sidebar; two-pane builder in 2b | ☐ |
| Quality | Accessibility (Dynamic Type/font scale, VoiceOver/TalkBack) | — | ◐ labels on every setup control, system text styles; device audit in Phase 6 | ☐ |
