# Phase 5 status (paywall, free-invoice counter, StoreKit 2)

- **As of:** 2026-10-08
- **Summary:** the free tier and the one-time unlock work end to end against a fake store and the local StoreKit
  configuration: 15 free invoices, only "Issue invoice" locked at the limit, purchase, Ask to Buy, cancel, restore
  and refund. What remains needs App Store Connect: the product record, prices per storefront, the sandbox matrix
  on a device and the IAP review screenshot.

## Tasks (plan § Phase 5)

| # | Task | Status | Evidence |
|---|---|---|---|
| 1 | `InvoiceBilling` implementing the `billing.md` state machine | ✅ | `EntitlementMachine` in core (25 `billing` fixtures, every transition); `StoreEntitlementService` (10 tests with a fake store) |
| 2 | A `.storekit` configuration for local testing | ✅ | `ios/InvoiceBuilder.storekit`, referenced by the InvoiceApp scheme's Run action |
| 3 | Counter hooked into `IssueDocument`, mirrored to the Keychain, checked across synced devices | ✅ | the count increments in the issue transaction (Phase 2); effective count = max(app_state, device mirror, Keychain, every invoice ever issued in the — synced — database); the Keychain mirror is raised after each issue and after a sync |
| 4 | Paywall at Issue at the limit and from Settings; localised price; restore; Ask to Buy | ✅ | `PaywallView` (price from `Product.displayPrice`, "Restore purchases", "Waiting for approval"); Settings → Unlimited invoices; a Home banner when 3 or fewer are left |
| 5 | The unlocked state across the app | ✅ | `Session.entitlement`, observed for the session's lifetime |
| 6 | Refund and revocation | ✅ | `Transaction.updates` → `revoked`; a refund seen at launch resolves "not owned" |
| 7 | Sandbox testing on a device | 🔲 account | needs the App Store Connect product (see below) |
| 8 | UK and India prices in App Store Connect | 🔲 account | |

## Definition of done

| Criterion | State |
|---|---|
| Unit tests for every state transition | ✅ 25 `billing` fixtures (shared with Android) + 10 service tests |
| Manual sandbox matrix: buy / cancel / Ask to Buy / restore on a second device / refund | 🔲 locally possible with the `.storekit` file (Xcode → Debug → StoreKit → Manage Transactions); the sandbox run needs the account |
| Existing documents stay accessible when locked | ✅ only `requestIssue` for invoices checks the entitlement; `EntitlementTests.atTheLimitOnlyIssuingAnInvoiceIsLocked` issues a quote at the limit |

## App Review checklist (guideline 3.1.1, 3.1.2)

- [x] The unlock is an In-App Purchase (non-consumable); nothing is sold outside the store.
- [x] "Restore purchases" is on the paywall and in Settings.
- [x] The price shown is the store's localised `displayPrice`; nothing is hard-coded.
- [x] It says what you get, that it is a one-time purchase, and that nothing already made is ever locked.
- [x] The app is fully usable below the limit and for everything except issuing invoices above it.
- [ ] The IAP's review screenshot (the paywall) and description in App Store Connect.

## Your next actions

1. Create the non-consumable `app.invoicebuilder.invoices.unlimited_invoices` (or `<your bundle id>.unlimited_invoices`
   if the bundle ID changes) in App Store Connect, Family Sharing on, and set the UK and India prices.
2. On a device with a sandbox account: buy, cancel, Ask to Buy (approve and decline), restore on a second device and
   refund through the StoreKit transaction manager, then tick the matrix in `spec/billing.md`.
