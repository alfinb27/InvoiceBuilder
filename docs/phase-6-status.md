# Phase 6 status (iOS polish, release readiness, beta, App Store launch)

- **As of:** 2026-10-09
- **Summary:** everything that can be done in code is done: an automated accessibility audit in CI with the
  issues it found fixed, design tokens raised to ≥ 5:1, a sample-business mode in onboarding, haptics, MetricKit
  diagnostics kept on the device, performance measured at 1,000 invoices, the store listing, privacy answers and
  the release ADR. The rest is the launch itself and needs the Apple account and real users: TestFlight, the beta,
  CloudKit Production, App Store Connect and the submission.

## Tasks (plan § Phase 6)

| Area | Status | Evidence / what is left |
|---|---|---|
| Accessibility: contrast | ✅ | `AccessibilityAuditTests` (Xcode audit on Home, Invoices, Clients, Items, Settings, Backup, the builder and onboarding). It found our light tokens at 4.3–4.6:1; `spec/design/tokens.json` now has brand `#1A5FD6`, tertiary `#5B6371`, warning `#9A4A0B`, success `#126B33` (all ≥ 5:1 on every background we use). Home's secondary buttons use neutral text. |
| Accessibility: Dynamic Type, VoiceOver, Reduce Motion | ◐ | system text styles everywhere; the audit's remaining flags are system components (listed in the test); 🔲 the manual device pass: VoiceOver through issue → share → record payment, XXL and AX5 text, Reduce Motion |
| Localisation | ⏭ deferred | English only in 1.0 (ADR-0017). Region wording follows the business's country (PIN code / Postcode, GST / VAT), which no String Catalog variant would improve. The catalog comes with Hindi in Phase 8. |
| Craft: empty states, sample data, haptics, icon, launch screen | ✅ / 🔲 icon | "Try it with a sample business" (India or UK, in memory, never saved; a banner leads to the real setup); success haptics on issue and on a recorded payment; the Home checklist steps aside once setup is complete; Home's stale "PDFs arrive next build" line removed; generated launch screen. 🔲 the final app icon with the brand name. |
| Diagnostics | ✅ | `Diagnostics` subscribes to MetricKit and keeps the newest 20 payloads on the device; Settings → About shares them on request (ADR-0011: nothing leaves on its own). The Sentry gate is decided in the beta. |
| Performance: 1,000 invoices | ✅ | `PerformanceTests`: list query 26 ms, dashboard 5 ms; `ListPerformanceTests`: four searches over 1,000 rows < 100 ms. 🔲 60 fps scrolling on a device (Instruments) |
| Line editor keyboard | ✅ | Return no longer closes the line (Done is ⌘↩), found through CI |
| Beta (TestFlight, 20–50 users, 5+ on iPhone + iPad, 2–3 weeks) | 🔲 account | |
| iPad QA matrix | ◐ | compact → full widths covered by the UI tests and screenshot tour; 🔲 iPad mini, keyboard + trackpad, Stage Manager on devices |
| Sync release checklist (CloudKit Production, privacy wording) | 🔲 account / ✅ wording | the listing's privacy section explains private iCloud data |
| Mac gate | 🔲 | needs a signed build ("Designed for iPad") |
| Store listing | ✅ draft | `docs/product/app-store-listing.md` (UK and India copy, keywords, privacy label, screenshot plan) |
| Release (phased, 7 days) | 🔲 account | |

## Definition of done

| Criterion | State |
|---|---|
| Zero open P0/P1 bugs | ✅ none known; the beta decides |
| Crash-free sessions ≥ 99.5% in the beta | 🔲 beta |
| Accessibility audit checklist complete | ◐ automated part passes; manual device pass pending |
| Release ADR written | ✅ ADR-0017 |

## Your next actions (in order)

1. Choose the brand name and bundle ID (`docs/product/naming.md`), create the App Store Connect record, the
   developer team and the IAP (`docs/phase-5-status.md`).
2. Turn on iCloud (`docs/phase-4b-status.md`, "Turning sync on") and run the two-device script.
3. Upload a TestFlight build, run the beta, then the manual accessibility pass and the iPad matrix on devices.
4. Deploy the CloudKit schema to Production, fill in the listing, submit app + IAP together, release phased.
