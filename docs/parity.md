# Feature parity (v1)

The scope contract for v1: a row is done when both columns are ticked. Update this file in the same change as the
feature. Status legend: ☐ not started · ◐ in progress · ☑ done · — not applicable.

| Area | Feature | Spec | iOS/iPadOS | Android |
|---|---|---|---|---|
| Core | All `spec/fixtures` pass (count = `make validate-spec` total, 184 at spec v0) | ☑ | ☐ | ☐ |
| Core | Tax engine (IN, GB, GENERIC) | ☑ v0 | ☐ | ☐ |
| Core | Numbering, status, formatting, amount in words, tax ID validation | ☑ v0 | ☐ | ☐ |
| Data | SQLite schema + migrations (GRDB / Room) | ☑ v0 | ☐ | ☐ |
| Setup | Onboarding (country, registration, business, tax ID, bank/UPI, logo, signature) | ☐ | ☐ | ☐ |
| Setup | Clients (B2B/B2C, addresses, tax ID) | ☐ | ☐ | ☐ |
| Setup | Item catalogue (unit, price, rate, HSN/SAC, inclusive flag) | ☐ | ☐ | ☐ |
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
| Adaptive UI | iPad split view + two-pane builder / tablet + foldable panes | ☐ | ☐ | ☐ |
| Quality | Accessibility (Dynamic Type/font scale, VoiceOver/TalkBack) | ☐ | ☐ | ☐ |
