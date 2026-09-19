# Phase 0 status

- **As of:** 2026-09-19
- **Summary:** all desk work is done. What remains needs accounts, full Xcode / Android Studio, or physical devices.

## Tasks

| # | Task | Status | Evidence |
|---|---|---|---|
| 1 | Monorepo, Makefile, CI skeleton, `CLAUDE.md` ×3, ADRs D1–D15 | ✅ Done | `Makefile`, `.github/workflows/spec.yml`, `CLAUDE.md`, `ios/CLAUDE.md`, `android/CLAUDE.md`, `docs/decisions/` (15 ADRs) |
| 2 | Compliance notes (GST Rule 46/49/5, GST 2.0 rates, VAT Notice 700 & 700/21, domestic reverse charge) with sources and dates | ✅ Done · 🔲 reviews to book | `docs/compliance/in-gst-invoice-rules.md`, `docs/compliance/uk-vat-invoice-rules.md` (10 + 8 open questions) |
| 3 | Spec v0: JSON Schemas, `IN`/`GB`/`GENERIC` configs, reference data, DB schema, `ENGINE.md`, `billing.md`, labels, tokens, fonts | ✅ Done | `spec/` — `make validate-spec` passes |
| 4 | Fixtures v0 (target ≈ 30 tax + others) | ✅ Done: **184 cases** (48 tax, 39 rounding, 25 format, 19 validation, 16 status, 14 words, 13 numbering, 7 distribute, 3 UPI) + a sample backup | `spec/fixtures/`, `spec/samples/` |
| 5 | PDF spike | ✅ Decided on desk evidence → **Option B, native drawing** (ADR-0006) · 🔲 device checks | `docs/spikes/pdf-spike.md`, `docs/spikes/pdf/` |
| 6 | Sync spike | ◐ Desk review done; schema fixed (`ON CONFLICT REPLACE` primary keys) · 🔲 compile needs Xcode · 🔲 two-device run | `docs/spikes/sync-spike.md`, ADR-0015 (Proposed) |
| 7 | Wireframes (8 screens × iPhone/iPad), design tokens, name check | ✅ Wireframes and tokens · ◐ name: pick a brand, reserve in App Store Connect | `docs/design/wireframes.html`, `spec/design/tokens.json`, `docs/product/naming.md` |
| 8 | Accounts (Apple, Google Play), privacy policy | 🔲 Needs you · ✅ privacy policy drafted | `docs/product/privacy-policy.md` |

## Definition of done (from the plan)

| Criterion | State |
|---|---|
| `make validate-spec` passes in CI | Passes locally; the CI workflow runs once the repo is pushed to GitHub |
| Every decision has an ADR | ✅ 15/15 |
| Spike ADR has scores and evidence | ✅ PDF (rubric 83 vs 60, PDFs in `docs/spikes/pdf/`); sync is still Proposed pending devices |
| Play account created | 🔲 Needs you |

## What changed during Phase 0 (already applied to the spec/ADRs)

1. **PDF:** Option B (native drawing from a shared layout spec). macOS WebKit dropped Devanagari glyphs from PDF output,
   didn't repeat table headers, and ignores CSS page-margin boxes. Plan impact: Phase 3 +2–3 dev-days, Phase 7b +2.
2. **Fonts:** bundle static Noto Sans + Noto Sans Devanagari (OFL). Variable fonts broke text extraction and size.
3. **Schema:** primary keys are `TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE` (SQLiteData sync rule); validator now
   also rejects RESTRICT/NO ACTION foreign keys and CloudKit-reserved column names.
4. **India checks:** the "unregistered buyer ≥ ₹50,000" rule now applies to domestic supplies only; exports check
   buyer name, address and country instead.
5. **Code-review fixes:** value-list CHECK constraints removed from synced tables; `schema.sql` is compared with the
   migrations structurally (additive `ALTER TABLE` migrations now pass); a buyer without a country is domestic
   (spec + 2 fixtures); `rate_not_effective` is one issue per document with `lines`, and issue order is specified;
   `make check-sync` requires the bundled copy once an app core module exists; every JSON file under `spec/` is
   schema-validated with Ajv in strict mode; one product ID on both stores.

## Your next actions (in order)

1. **Install Xcode** (current release, from the App Store): Phase 1, the sync-spike compile and all iOS device checks
   need it (Command Line Tools lack SwiftUI macro plugins).
2. **Create the Google Play Console account now**: identity verification takes days, and a new personal account must
   run a 14-day closed test with 12+ testers before production (an organisation account needs a D-U-N-S number).
3. **Apple Developer Program + Paid Apps Agreement** (banking/tax), then **choose the app name and bundle ID**
   and reserve the name by creating the App Store Connect record (`docs/product/naming.md`).
4. **Book the reviews:** an Indian CA and a UK accountant, half a day each, with `docs/compliance/*.md` and the
   `explain` lines of `spec/fixtures/tax/*.json`.
5. **Publish the privacy policy** (`docs/product/privacy-policy.md`) at a public URL.
6. **Run the device spikes** when Xcode is installed: `docs/spikes/sync-spike.md` (two devices, one Apple ID) and the
   PDF device checks in `docs/spikes/pdf-spike.md` (Android can wait until Phase 3 starts).
7. **Push the repo to GitHub** so the `spec` CI workflow runs.
