# Overdue reminders (v0)

Normative for local overdue-payment reminders on both apps: eligibility, the scheduling/reconciliation algorithm,
and the "Send reminder" share action. iOS implements it in `InvoiceCore` (`ReminderCandidate`,
`ReminderScheduler`), a `UserNotifications` adapter in `InvoiceUI`/`InvoiceData`, and the reconciler hook at app
launch; Android in `:core:domain` and a daily `WorkManager` job, with the same names (ADR-0013). Field shapes are
in `schema/domain.schema.json#/$defs/Business` (`reminderDaysAfterDue`) and `#/$defs/Document`
(`reminderDaysAfterDueOverride`). The scheduling algorithm is proven by `fixtures/reminders/*.json` (kind
`reminder`). Record rules (ids, timestamps, trimming) are `setup.md` §1.

## 1. Default and override

- `business.reminderDaysAfterDue` (`setup.md` §4, 0–60 or `null`) is the business-wide default: "remind N days
  after the due date." `null` means no reminders unless a document overrides it.
- `document.reminderDaysAfterDueOverride` (0–60 or `null`) overrides the default for one invoice. `null` defers
  to the business default; a document created before this field existed has `null` and behaves exactly as before.
- Effective days = `overrideDays ?? businessDefaultDays`. `null` effective days means the invoice is never
  scheduled.

## 2. Eligibility

A candidate for a reminder is an invoice (never a quote) where all of the following hold:
- `lifecycle = issued`
- `dueDate` is set
- the derived status (`ENGINE.md` §6) is not `paid` and not `void`
- the effective days (§1) is not `null`

Ineligible invoices are simply not scheduled; nothing is written for them.

## 3. Scheduling and reconciliation

`ReminderScheduler.plan(businessDefaultDays, cap, candidates) → scheduled` is a pure function: for each eligible
candidate (§2), `remindOn = candidate.dueDate + effectiveDays` (plain calendar-day addition, no timezone, as
`documents.md` §2's date arithmetic); the result is every `{ documentId, remindOn }` pair, sorted by `remindOn`
ascending (ties broken by `documentId`), truncated to the first `cap` entries.

- iOS calls this with `cap = 50`, since iOS allows at most 64 pending local notifications system-wide and this
  app reserves the nearest 50 for reminders (ADR-0013); the far-future remainder is picked up on a later
  reconciliation pass instead of being scheduled now.
- **Reconciliation** re-runs the plan and replaces every pending local reminder with the new result. It runs:
  on app launch; after a payment is recorded (§`documents.md` §10); after a document is voided (§`documents.md`
  §11); after a due date, the business default, or a per-invoice override changes. It is a callable unit, not
  inlined into launch-only code, so a future sync pass (Phase 4b) can invoke it after remote changes without a
  rewrite — this spec does not define sync-triggered reconciliation.
- A reminder that fires shows the invoice number, the client name and the outstanding amount.

## 4. "Send reminder"

A manual action, available on any invoice whose derived status (`ENGINE.md` §6) is not `paid` and not `void`,
that opens the OS share sheet with one prefilled message and the invoice's PDF attached (reusing the existing PDF
share flow, `pdf/RENDERING.md`). The share sheet itself offers the channel choice (WhatsApp, Mail, etc.) — this
app does not implement per-channel formatting.

Message template (placeholders in `{}`; `formatMoney`/`formatDate` per `ENGINE.md` §7):

```
Hi {buyerSnapshot.contactName ?? buyerSnapshot.name}, this is a reminder that invoice {number} for
{formatMoney(outstanding)} from {sellerSnapshot.name} was due on {formatDate(dueDate)}.{upiLine} Thank you!
```

`{upiLine}` is `" Pay via UPI: {upiLink}"` when `ENGINE.md` §9's UPI link is defined for this document (INR,
UPI ID present, outstanding > 0), otherwise empty. A document without a `buyerSnapshot` (no client) uses
"Hi there," instead of the greeting clause.

## 5. Fixtures

`fixtures/reminders/*.json` (kind `reminder`) proves `ReminderScheduler.plan`: eligibility per derived status,
override-vs-default precedence, a `null` effective days producing no reminder, and the `cap` truncation ordering
by `remindOn`.
