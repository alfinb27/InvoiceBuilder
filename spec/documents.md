# Documents: drafts, issuing, duplicating and converting (v0)

Normative for the document features of both apps: invoice and quote drafts, the builder's defaults, issuing
(`IssueDocument`), duplicating, converting a quote, deleting a draft, recording payments, voiding and the quote
accept/decline outcomes. iOS implements it in `InvoiceCore` (`DocumentRules`, `LinePricing`, `NumberAllocator`,
`DocumentService`, `PaymentRepository`, `PaymentService`), `InvoiceData` (`GRDBDocumentRepository`,
`GRDBDocumentService`, `GRDBPaymentRepository`, `GRDBPaymentService`) and `InvoiceUI` (the builder); Android in
`:core:domain`, `:core:data` and `:app`, with the same names. Field shapes are in
`schema/domain.schema.json#/$defs/Document` and `#/$defs/Payment`; tax results come only from `TaxEngine.compute`
(`tax/ENGINE.md`). Pure functions here are proven by `fixtures/documents/*.json` (kind `document`); derived status
is proven by `fixtures/status/*.json` (kind `status`). Record rules (ids, timestamps, trimming, tombstones) are
`setup.md` §1.

## 1. Lifecycle

| Lifecycle | Number | Editable | Deletable | Tax results |
|---|---|---|---|---|
| `draft` | none | yes, autosaved | yes (tombstone) | recomputed on every change; totals columns stored, `computed` = `NULL` |
| `issued` | allocated at issue, never changes | deferred (revision) | never | frozen at issue |
| `void` | kept | no | never | kept (§11) |

- Drafts refer to the **live** business and client and re-take both snapshots (§4) on every save.
- **Issuing** freezes the snapshots, allocates the number and stores the `ComputedDocument` (§6).
- Display status is derived (`ENGINE.md` §6), never stored; `paid` is the sum of an invoice's live payments (§10).
- Payments (§10), void (§11) and the quote outcomes accepted/declined (§12) are specified below. Revising an
  issued document remains deferred.

## 2. New drafts

A new document is written on its first change (or its first line), never when the builder merely opens.

| Field | Invoice | Quote |
|---|---|---|
| `issueDate` | today | today |
| `dueDate` | `issueDate + business.paymentTermsDays` days | `null` |
| `validUntil` | `null` | `issueDate + 30` days |
| `currency` | `client.defaultCurrency ?? business.homeCurrency` | same |
| `supplyType` | §2.1 | same |
| `notes`, `terms`, `templateId` | the business defaults (`defaultNotes`, `defaultTerms`, `templateId`) | same |
| `taxConfigRef` | the `ref` of the business's config family in force on `supplyDate ?? issueDate` | same |

Everything else starts empty: `supplyDate`, `exchangeRate`, `placeOfSupply`, `discount`, `clientId` = `null`;
`reverseCharge` and `pricesIncludeTax` = `false`; `roundOff` = `null` (the config default), except that a
foreign-currency document starts with `roundOff = false` (rounding a total to a whole unit is a home-currency
convention); `shippingMinor = 0`; `revision = 0`; no lines; totals 0.

### 2.1 Supply type
The first `config.supplyTypeDefaults` entry whose `when` matches, else the first `config.supplyTypes` entry. Keys
(all listed keys must match):

| Key | True when |
|---|---|
| `buyerForeign` | a client is chosen and its `countryCode` ≠ the business `countryCode` |
| `buyerIsBusiness` | a client is chosen and `isBusiness` |
| `sellerHasLutReference` | `business.extraIds.lutReference` is not empty |

IN: a foreign client defaults to `exportWithoutTax` when the business has a LUT reference, else `exportWithTax`.
GB: a foreign business client defaults to `exportServicesB2B`. Everything else defaults to `domestic`.

### 2.2 Changes that move other fields (drafts)
- **Client chosen or changed:** `currency`, `supplyType` and `roundOff` are set again as for a new draft with that
  client; `placeOfSupply` is cleared; `exchangeRate` is cleared when the currency changes.
- **Currency changed:** `exchangeRate` is cleared; `roundOff` = `false` for a foreign currency, `null` for the home
  currency.
- **Issue date changed:** `dueDate` and `validUntil` (when set) move by the same number of days.
- **Type changed** (invoice ↔ quote): the target type's `dueDate` / `validUntil` defaults apply from `issueDate`.
- **Prices-include-tax toggled:** line prices are not converted; the toggle says how typed prices are read.

## 3. Lines

- Positions are `0…n−1` in display order; reordering, inserting or removing renumbers them.
- **From the catalogue:** `catalogItemId` = the item, `description` = `item.name`, `productCode`, `unit` and `rateId`
  from the item, `quantity = "1"`, `unitPriceMinor` = `linePrice` (§3.1), no discount.
- **One-off line:** `quantity = "1"`; `rateId` = the previous line's rate; with no previous line, the first rate in
  force when the seller does not charge tax (the rate is not shown then), otherwise none (the user picks one).
- **Duplicate line:** a copy with a new id inserted after the original.
- A line needs a non-empty `description`, a spec decimal `quantity` ≥ 0, `unitPriceMinor` ≥ 0 and a `rateId` before
  the document can be issued (§6).

### 3.1 `linePrice(item, document) → unitPriceMinor | exchange_rate_missing`
Converts a catalogue price (home currency, its own price basis) to the document's currency and price basis, with
one rounding (`round(x, config.rounding.amountMode)`, `ENGINE.md` §2.2):

- **Basis factor** `b`: when the seller's registration charges tax and `item.priceIncludesTax ≠
  document.pricesIncludeTax`, with `R` = the rate's effective percent: inclusive → exclusive `b = 100 / (100 + R)`;
  exclusive → inclusive `b = (100 + R) / 100`. Otherwise `b = 1`.
  - `R` for a config rate is its `percent`. For a custom rate, start with `acc = 0` and for each component in order
    add `(100 + (compound ? acc : 0)) × percent / 100` to `acc`; `R = acc` (5% + compound 10% → `15.5`).
- **Currency factor** `c`: `1` when `item.currency = document.currency`; else, when `item.currency` is the home
  currency and `document.exchangeRate` is set, `c = 10^(docExp − homeExp) / exchangeRate`; otherwise the result is
  `exchange_rate_missing` (the builder adds the line with price 0 and asks for the price).
- `unitPriceMinor = round(item.unitPriceMinor × b × c, amountMode)`.

### 3.2 The "Add an item" sheet (`OneOffLine`)
Lines are added and edited in one sheet (ADR-0020, `docs/design/design.md` §6.5) with two tabs: **My saved items**
(each tap adds a catalogue line, as above) and **Something new** (a one-off line).

- **Fields:** "What did you sell?" (`description`), "How many?" (`quantity`, a stepper that also takes typed decimals),
  "Price for one" (typed in the document currency, §11 of `setup.md`), the rate, and, folded under "More details",
  unit, product code and line discount. The product code is shown unfolded when the config needs it on this
  document (IN: a B2B invoice, `ENGINE.md` Step 12).
- **Rate chips** (`RateChips`): the ids of the config family in `design/rate-chips.json`, in that order, that are in
  force on `supplyDate ?? issueDate`; a family that is not listed shows the business's own rates (`customRates`) in
  force, at most `maxChips`. Every other rate in force is under "Other rates" (`rateChoices`). The line's rate starts
  as `oneOffRateID` (§3). Not shown when the seller's registration does not charge tax.
- **"My price already includes {taxName}"** (shown only when the registration charges tax) says how the typed price
  is read. It starts as `document.pricesIncludeTax`. When the draft has **no other line** (the first line, or the only
  line being edited), the switch sets `document.pricesIncludeTax` and the typed price is the line's `unitPriceMinor` as
  typed. Otherwise, when the switch
  differs from `document.pricesIncludeTax`, the typed price is converted to the document's basis with the §3.1 basis
  factor `b` of the chosen rate and one rounding (`round(price × b, amountMode)`), exactly as a catalogue item with
  `priceIncludesTax` = the switch.
- **The live line total** is the engine's result for this line alone (taxable amount, tax and total, ENGINE.md), so
  it matches what the document will show.
- **"Save to my items so I can reuse it"** (on by default; offered only when the document currency is the home
  currency): Add also creates a catalogue item (§10 of `setup.md`) with `name` = the description, `kind` = `service`,
  `unit` = the line's unit or the kind's default, `unitPriceMinor` = the typed price, `priceIncludesTax` = the switch
  (`false` when tax isn't charged), `rateId` and `productCode` of the line; the line's `catalogItemId` is that item.
- **Editing** an existing line opens the same sheet without tabs, with Duplicate and Delete. The switch then starts
  as `document.pricesIncludeTax` and the price as stored.

### 3.3 Payment-term chips
Invoices: "When should they pay?" offers chips for 0 ("Right away"), 7, 15 and 30 days, plus
`business.paymentTermsDays` when it is not one of those; a chip sets `dueDate = issueDate + n` days. The selected chip
is the one matching `dueDate − issueDate`, if any; any other due date is picked under More options. Quotes: "How long
is this quote valid?" with 7, 15, 30 and 60 days setting `validUntil` the same way.

## 4. Snapshots

`sellerSnapshot` and `buyerSnapshot` are the engine's `seller` / `buyer` (`ENGINE.md` §1) plus display fields, in one
flat JSON object each. Empty text is omitted.

- **Seller:** `registration`, `taxId`, `region` (the business address `regionCode`, else read from the tax ID),
  `country`, `homeCurrency`, `lutReference`, `address` (the business address on one line: `line1, line2, city
  postalCode`), `turnoverMinor`, `customRates`; display: `name`, `legalName`, `postalAddress` (the `address` object),
  `email`, `phone`, `website`, `extraIds`, `bank`, `upiVpa`, `logoAssetId`, `signatureAssetId`.
- **Buyer** (only when a client is chosen): `name`, `address` (billing address on one line), `country`, `region`,
  `taxId`, `isBusiness`; display: `contactName`, `email`, `phone`, `billingAddress`, `shippingAddress`.
- **Without a client** the engine buyer is `{ isBusiness: false }` (a domestic walk-in customer) and
  `buyerSnapshot = null`.
- If the client of a draft has been deleted, the draft keeps its last buyer snapshot and the builder shows the
  client as removed.

## 5. Saving a draft (autosave)

The builder saves 500 ms after the last change and when it closes. A save writes, in one transaction:
the document row (both snapshots re-taken from the live business and client; the totals columns from the engine
result, or 0 when the engine returns an error; `computed = NULL`), every current line (update by id, insert new ones;
`rate_snapshot` and the computed line columns `NULL`), and a tombstone for every stored line no longer in the draft.
Closing the builder on a draft with no client and no lines deletes it (§9).

## 6. Issuing (`IssueDocument`)

One write transaction; any failure leaves the database unchanged.

1. Load the draft (live, lifecycle `draft`), its live lines, the live business and the live client (if any).
2. Take both snapshots (§4) and the config in force on `supplyDate ?? issueDate`; compute.
3. **Blocking problems** (none may remain, else nothing is written):
   `no_lines`; `line_description_missing` (line indexes); `line_rate_missing` (line indexes, a line without a rate);
   the engine error (`code`, `line`); every engine issue with severity `error`.
4. **Series:** the live `numbering_series` of the document type whose `ownerDeviceId` is this device (earliest
   `createdAt`, then lowest `id`); none → `no_series`.
5. **Number** (`NumberAllocator`, `ENGINE.md` §5): `periodKey` from `issueDate`; `sequence =
   max(counters[periodKey] ?? 1, 1)`; `number = format(pattern, …, sequence)`; `number_too_long` /
   `number_invalid_chars` are blocking. Then `counters[periodKey] = sequence + 1`.
6. **Write:** the document gets `lifecycle = issued`, `number`, `seriesId`, `periodKey`, `sequence`, both snapshots,
   `taxConfigRef` of the config used, `revision = 1`, the totals columns and `computed` (the full
   `ComputedDocument`). Each line gets `rateSnapshot = { percent: computed rate, category, label }`, `amountMinor`,
   `taxableMinor`, and, when the config rounds tax per line, `taxMinor` (Σ its taxes) and `totalMinor = taxable +
   tax` (both `NULL` when tax is rounded per invoice). One `tax_line` row per `computed.taxLines` entry
   (`line_id = NULL`, same component, rate, category, taxable, tax, charged).
7. **Invoices only** (never quotes or drafts): the free-tier counter increments (`billing.md`): `app_state`
   key `issued_invoice_count` (+1, created at 1) and `device_state.free_counter_mirror` (+1).

The next number offered in Settings (`setup.md` §6) must stay above the highest `sequence` already issued in that
series and period.

### 6.1 Review & send (the screens)
The screens call issuing **Send** (ADR-0020). "Review & send" in the builder first runs the checks of step 3 (and the
free-tier and series checks, `billing.md`, `sync.md` §3); any problem is shown in the builder and nothing else
happens. Otherwise the review screen shows the client, total, item count and due date, the number the document will
get (the preview of step 5; the number is allocated only when it is sent), that sending locks it, the channel
(WhatsApp, Email, Print, Save PDF) and what happens next. Its button issues the document and then opens the chosen
channel with the PDF (§8). "Keep as draft" closes the review and leaves the draft as it is.

## 7. Duplicate and convert

- **Duplicate** (any live document) → a new draft of the same type: new ids for it and its lines; `issueDate` =
  today; `dueDate` / `validUntil` = the §2 defaults from today; client, currency, exchange rate, supply type, place of
  supply, reverse charge, prices-include-tax, round-off, discount, shipping, notes, terms, template and lines
  (position, catalogue link, description, product code, unit, quantity, price, discount, rate) are copied; number,
  series, period, sequence, sent/void fields, quote outcome, `convertedFromId`, `computed` and the computed line
  columns are not. It is saved at once (§5), which re-takes both snapshots (a deleted client's last buyer snapshot is
  kept, as for any draft).
- **Convert quote** (an issued, live quote whose `quoteOutcome` is not `converted`) → a new invoice draft built like a
  duplicate, with `docType = invoice`, `convertedFromId` = the quote, `dueDate` = today + payment terms and
  `validUntil = null`; in the same transaction the quote's `quoteOutcome` becomes `converted`. The quote's content
  never changes. Otherwise the error is `not_convertible`.

## 8. Sharing

Channels: **WhatsApp** (Android: WhatsApp with the PDF when it is installed, else the share sheet; iOS: the share
sheet, where WhatsApp is one tap, as iOS can't hand a PDF to one chosen app), **Email** (a new
email to the buyer snapshot's `email` with the PDF attached, else the share sheet), **Print** (the system print
dialog) and **Save PDF** (the system "save to files" picker); the share sheet is also always available from the
preview. The shared file is named "{Invoice|Quote} {number}.pdf" with each `/` of the number as `-`
("Invoice INV-26-27-0001.pdf"); a draft's is "{Invoice|Quote} draft.pdf".

Sharing, printing or saving an issued document's PDF offers to mark it as **sent**: `sentAt` is set to the moment
the user accepts, and the derived status becomes `sent` (`ENGINE.md` §6). The prompt appears whenever an issued
document that is not marked sent leaves the app, and stops once it is; declining leaves the document unchanged, so
the next share asks again. Marking it sent again is harmless — the timestamp is replaced. Nothing else about the
document changes, and a draft is never marked sent.

## 9. Deleting a draft

Only drafts can be deleted: the document gets a tombstone (its lines are unreachable through it). Saving that
draft again (its builder is still open, §5) revives it with the new content, so no edit is ever lost. If it was
converted from a quote and no other live document has the same `convertedFromId`, the quote's `quoteOutcome` returns
to `null`. Deleting an issued or void document is the error `not_a_draft`.

## 10. Recording a payment

One write: an issued invoice may receive any number of payments.

- Precondition: `docType = invoice`, `lifecycle = issued`. Recording a payment on a draft or void invoice, or on
  any quote, is the error `not_payable`.
- Writes one `Payment` row (`businessId`, `documentId`, `amountMinor` > 0, `date`, `method`, optional `reference`,
  `note`); the document row itself is never touched. `paid` = the sum of `amountMinor` over the invoice's live
  payments; derived status and `outstanding` are always computed from that sum, never stored (`ENGINE.md` §6).
- `amountMinor` may exceed the invoice's current outstanding amount: it is stored as given, never clamped or
  rejected (a UI may warn on overpayment, but storage must not, so a backup round trip stays lossless).
- Correcting a payment: delete it (tombstone, `setup.md` §1) and record a new one in its place; there is no
  in-place amount edit.
- Voiding an invoice (§11) does not delete its payments; they remain as history, and its status stays `void`
  regardless of them (`ENGINE.md` §6 puts `void` first in the precedence order).

## 11. Void a document

One write: turns a live `issued` invoice or quote into `void`.

- Precondition: `lifecycle = issued`. Voiding a `draft` (delete it instead, §9) or an already-`void` document is
  the error `not_voidable`.
- Requires a non-empty `voidReason` (free text, trimmed per `setup.md` §1; empty after trimming is rejected, not
  stored as `NULL`).
- Writes `lifecycle = void`, `voidedAt = now`, `voidReason`. Its `number`, snapshots, `computed` result and any
  payments are unchanged and kept — voiding never reclaims the number (`ENGINE.md` §5).
- Terminal: void cannot be reversed. A mistaken void is corrected by issuing a new document, never by un-voiding.

## 12. Quote outcome: accept or decline

One write: records the buyer's response to an issued quote, outside of converting it to an invoice (§7).

- Precondition: `docType = quote`, `lifecycle = issued`, and `quoteOutcome` is `null` or the other of
  `accepted`/`declined` (the buyer can change their mind). A `converted` quote cannot be reopened (`already_converted`);
  a `draft` or `void` quote cannot be accepted or declined (`not_a_live_quote`).
- Writes `quoteOutcome = accepted` or `declined`. `validUntil` having already passed does not block the action —
  an expired quote can still be accepted or declined late, since expiry is a display-time computation only
  (`ENGINE.md` §6; proven by fixture `status-quote-accepted-after-expiry`).
- Does not affect lines, totals or any other field.
