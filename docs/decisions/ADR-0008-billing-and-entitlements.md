# ADR-0008: Billing and entitlements

- **Status:** Accepted
- **Date:** 2026-09-19

## Decision
- One non-consumable product with the same ID on both stores, `<appId>.unlimited_invoices`
  (e.g. `app.invoicebuilder.unlimited_invoices`; see `spec/billing.md`), validated on-device: StoreKit 2 signed transactions (iOS);
  Play Billing Library 8+ one-time product (Android). No server validation (no backend in v1).
- Free tier: 15 issued invoices per user, lifetime. Drafts and quotes never count; the counter never decreases.
  With iCloud sync the limit uses `max(local counter, issued invoices across synced devices)`.
- At the limit only "Issue invoice" is locked; existing documents stay fully usable.
- State machine and product IDs: `spec/billing.md`.

## Consequences
- Android must acknowledge purchases within 3 days and treat `PENDING` (UPI/cash) purchases as not yet owned.
- Reinstall can reset the counter where Keychain/Block Store mirrors fail — accepted for a low-price unlock.

## Revisit when
A subscription tier (e.g. cross-platform sync) needs server notifications → small backend.

## Phase 5 (2026-10-08)
- The state machine is a pure function in core (`EntitlementMachine.next`), proven by `billing` fixtures that
  Android will run too. StoreKit sits behind `StoreClient`, so every purchase flow is unit-tested with a fake store.
- Issuing an invoice is allowed whenever the state is `unlocked` or the count is below 15, in every state: an
  unresolved store (offline first launch) or a pending Ask to Buy never blocks someone who is below the limit.
- Product ID = `<bundle id>.unlimited_invoices` (today `app.invoicebuilder.invoices.unlimited_invoices`).
