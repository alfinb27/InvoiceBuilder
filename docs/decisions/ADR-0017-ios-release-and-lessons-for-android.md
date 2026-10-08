# ADR-0017: iOS 1.0 release scope, and what the Android port inherits

- **Status:** Accepted (release steps that need the Apple account are listed in `docs/phase-6-status.md`)
- **Date:** 2026-10-09

(ADR-0016, foldable iPhone support, lives on `main` and is unaffected.)

## Context
Phases 1–5 and the code side of Phase 6 are done. The plan asks for a release ADR that records what 1.0 ships
with and what was learned that the Android port (Phase 7) must carry over.

## Decision
**1.0 ships:** invoices and quotes for India (GST), the UK (VAT) and everywhere else (own rates); PDFs in four
templates with UPI QR; payments, status, dashboard and reminders; backup and restore; iCloud sync between Apple
devices (switched on by the build once the container exists); 15 free invoices, then one non-consumable unlock.
English only; all storefronts; phased release over 7 days.

**Not in 1.0:** a String Catalog and Hindi (region wording already follows the *business's* country — PIN code vs
Postcode, GST vs VAT — which is what users expect regardless of device language); the Mac build (decided at the Mac
gate); credit notes; multi-currency dashboards.

## Lessons for Android (Phase 7)
1. **Spec first paid off every time.** Every feature that had fixtures (tax, numbering, status, reminders, backup,
   series, billing) needed no rework when the UI arrived; port the fixture runners before any screen.
2. **Validate references and cycles in the schema tooling, not on a device.** SQLiteData rejected a self-reference
   only when the engine started; `make validate-spec` now catches cycles. Room has no such check: keep relying on
   the validator.
3. **Migration 0004 rebuilds a table.** Room must run it with foreign keys off (`PRAGMA foreign_keys=OFF` before,
   `foreign_key_check` after), exactly as GRDB does, or dropping `document` cascades to every line and payment.
4. **Backups carry tombstones** and restore never deletes: port `GRDBBackupService.replaceAll` row for row, and
   run `fixtures/backup` plus the iOS-made sample file in `spec/samples`.
5. **Pure state machines for anything with a store or a clock** (`EntitlementMachine`, `ReminderScheduler`):
   Play Billing goes behind the same seam, with `PENDING` mapping to `purchasePending`.
6. **Keyboard shortcuts must not take plain Return** in forms: on iOS a `.defaultAction` button closed the line
   editor from its first field. On Android, IME actions should move focus (`ImeAction.Next`), with Done only on
   the last field.
7. **Test on the CI's (older) toolchain early.** Two bugs only showed up on GitHub's runner; Android CI should
   test on the lowest supported API level as well as the newest.
8. **Accessibility audits find real issues:** the design tokens were at 4.3–4.6:1 on our own backgrounds. The
   tokens are now ≥ 5:1 in light mode; Android uses the same `spec/design/tokens.json`.

## Consequences
The Android port starts from a spec at fixture count 410 and the parity table in `docs/parity.md`.

## Revisit when
Beta feedback changes behaviour (then the spec changes first, before Android copies it).
