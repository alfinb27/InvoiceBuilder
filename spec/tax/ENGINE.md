# TaxEngine specification (v0, draft for professional review)

This document is **normative**: `InvoiceCore` (Swift) and `:core:domain` (Kotlin) implement exactly these rules,
and `spec/fixtures/` are the answer key. When code and this document disagree, fix the code or change this
document together with the fixtures, never silently.

`TaxEngine.compute(input) → ComputedDocument` is a pure function: no clock, no locale, no I/O.

## 1. Input

```
EngineInput {
  config  : TaxConfig                  // one of spec/tax/*.json
  seller  : { registration, taxId?, region?, country, homeCurrency, lutReference?, address?,
              turnoverMinor?, customRates? }
  buyer   : { name?, address?, country?, region?, taxId?, isBusiness }
  draft   : { docType: "invoice" | "quote", issueDate, supplyDate?, currency, exchangeRate?,
              supplyType, placeOfSupply?, reverseCharge = false, pricesIncludeTax = false,
              lines: [Line], discount?: Discount, shipping? (minor units), roundOff? }
}
Line     { description?, productCode?, quantity: DecimalString, unitPrice: Int64 minor, discount?: Discount,
           rateId }
Discount { type: "percent", value: DecimalString } | { type: "amount", value: Int64 minor }
```

- Money is `Int64` minor units of `draft.currency` (exponent from `spec/reference/currencies.json`).
- `DecimalString` matches `^-?(0|[1-9][0-9]*)(\.[0-9]+)?$`. Parse strictly; reject anything else.
- v0 does not support negative quantities, prices or totals (credit notes come later).

## 2. Primitives

### 2.1 Decimal arithmetic
Multiplication and addition are exact. Division is carried to at least 34 significant digits (decimal128
precision), rounding half-even at the last digit, before any rounding below.

### 2.2 `round(x, mode) → Int64`
`x` is a decimal amount in minor units. Modes, by meaning:

| Mode | Rule | 2.5 | -2.5 | 2.4 | 2.6 |
|---|---|---|---|---|---|
| `halfAwayFromZero` | nearest integer; exact halves go away from zero | 3 | -3 | 2 | 3 |
| `halfEven` | nearest integer; exact halves go to the even neighbour | 2 | -2 | 2 | 3 |
| `towardZero` | drop the fraction | 2 | -2 | 2 | 2 |

Implement these directly; do not rely on library enum names (Foundation `.down` rounds toward −∞ for negatives,
Java `RoundingMode.DOWN` rounds toward zero).

### 2.3 `distribute(total, exacts) → [Int64]`
Splits a non-negative integer `total` over items whose exact (unrounded) shares are `exacts` (all ≥ 0), so the
parts sum to `total`:
1. `part_i = floor(exact_i)`.
2. `r = total − Σ part_i` (0 ≤ r ≤ n by construction in every use below).
3. Add 1 to the `r` items with the largest fractional part `exact_i − floor(exact_i)`; ties go to the lower index.

### 2.4 `allocateProportional(total, weights) → [Int64]`
`distribute(total, [total × w_i / Σw])`. If `Σw = 0`, the first item receives the whole total.

## 3. Algorithm

### Step 0: context
- `reg = config.registrations[seller.registration]`; `chargesTax = reg.chargesTax`.
- `effectiveDate = draft.supplyDate ?? draft.issueDate`.
- `sellerRegion = seller.region ?? (taxIdFormat.regionFromPrefix ? first N chars of seller.taxId : null)`.
- Place of supply (only when `config.regions` is non-empty):
  `placeOfSupply = draft.placeOfSupply ?? (buyer.country is set and ≠ config.country ? config.foreignRegion : buyer.region ?? sellerRegion)`.
  A buyer **without a country is domestic** (walk-in customers, quick B2C bills): their region is used if set,
  otherwise the seller's region. Only an explicit foreign country selects `foreignRegion`.
- `sameRegion = placeOfSupply ≠ null && placeOfSupply == sellerRegion`.
- `foreignCurrency = draft.currency ≠ seller.homeCurrency`.
- `reverseCharge = draft.reverseCharge && config.reverseCharge.supported && chargesTax`.
- `inclusive = draft.pricesIncludeTax && chargesTax && !reverseCharge`.

### Step 1: component rule
Only when `chargesTax`. Take the **first** `componentRules` entry whose `when` matches every key it lists
(array keys match if the value is in the array; booleans must be equal). No match → error `no_component_rule`.

### Step 2: line amounts
For each line `i`:
- `gross_i = quantity_i × unitPrice_i` (exact).
- Line discount: percent → `gross_i × value / 100`; amount → `value`.
- `amount_i = round(gross_i − lineDiscount_i, rounding.amountMode)`.
- `rate_i` = `rateId` looked up in `config.rates` (or `seller.customRates` when `ratesFrom = business`).
  Unknown id → error `unknown_rate`. A rate not in force on `effectiveDate` (outside `[effectiveFrom, effectiveTo]`)
  is still applied; the document then gets **one** issue `rate_not_effective` (warning) whose `lines` lists every
  affected line (0-based indexes, ascending).
- `subtotal = Σ amount_i`.

### Step 3: invoice discount
- `D` = percent → `round(subtotal × value / 100, amountMode)`; amount → `value`. `D > subtotal` → error
  `discount_exceeds_subtotal`.
- `alloc = allocateProportional(D, amount)`; `net_i = amount_i − alloc_i`.

### Step 4: shipping
`S = draft.shipping ?? 0` (same price basis as the lines: inclusive when `inclusive`). Shipping is never
discounted. If `S > 0` it becomes pseudo-lines, according to `config.shipping.rule`:
- `principalSupplyRate`: one pseudo-line of `S` at the rate of the line with the largest `net_i` (ties → lowest index).
- `apportion`: group lines by `rateId` (groups ordered by first appearance); split `S` with
  `allocateProportional(S, Σ net per group)`; one pseudo-line per group at that group's rate.

Shipping pseudo-lines are taxed exactly like lines (Steps 5–6) and reported under `shipping`.

### Step 5: components per line
When `chargesTax`, each line (and shipping pseudo-line) gets an ordered component list:
- `components = "fromRate"`: the rate's own `components` (`code`, `percent`, `compound`).
- Otherwise, for each rule component: `code` (`$localComponent` → the place-of-supply region's
  `localComponent`), `percent = rateOverride ?? rate.percent × share`, `category = categoryOverride ?? rate.category`.
- After overrides, if a line's components have category `exempt`, `nil` or `outsideScope`, the line carries no tax:
  its components are replaced by a single non-tax group `{ component: null, category, rate: "0" }`. (Zero-rated
  supplies, category `zero`, keep their component at 0%, e.g. `IGST 0%` for exports under LUT, `VAT 0%`.)
- `R_i` = sum of the line's component percents. Compound components are not allowed together with `inclusive`
  (error `inclusive_compound_unsupported`).

When `!chargesTax`, lines carry no components and `taxable_i = net_i`.

### Step 6: taxable value and tax
A **tax unit** is a line when `taxLevel = line`. When `taxLevel = invoice`, amounts are computed exactly per group
and rounded once per component code across the invoice (see below).

**Exclusive** (`!inclusive`, including every reverse-charge document):
- `taxable_i = net_i`.
- Line level: `tax_{i,c} = round(base × percent_c / 100, taxMode)`, where `base = taxable_i`, plus the earlier
  components' tax for a `compound` component.
- Invoice level: for each group `g` = (component code, percent, category), `exact_g = Σ_{i∈g} taxable_i × percent / 100`.
  For each component code `c`: `T_c = round(Σ_{g∈c} exact_g, taxMode)`, then the group amounts are
  `distribute(T_c, [exact_g …])`.

**Inclusive** (prices entered with tax):
- Line level: for each component `c`, `tax_{i,c} = round(net_i × percent_c / (100 + R_i), taxMode)`;
  `taxable_i = net_i − Σ_c tax_{i,c}`. The typed total is therefore kept exactly, and equal-share components
  (CGST/SGST) are always equal.
- Invoice level: group lines by identical component set; `incl_g = Σ net_i`;
  `exact_{g,c} = incl_g × percent_c / (100 + R_g)`; per code `c`: `T_c = round(Σ_g exact_{g,c}, taxMode)` and
  `distribute(T_c, [exact_{g,c} …])`; `taxable_g = incl_g − Σ_c tax_{g,c}`. For display, the group's total tax is
  split across its lines with `distribute(Σ_c tax_{g,c}, [net_i × R_g / (100 + R_g) …])` and
  `taxable_i = net_i − thatShare`.

**Reverse charge:** computed as exclusive; every tax line has `charged: false` and is excluded from `tax` and
`total` (reported as `taxNotCharged`).

### Step 7: tax lines
Aggregate lines and shipping by (component, rate, category, charged) into `taxLines`, each with `taxable`
(Σ taxable of member lines) and `tax`. Order: by the first line (then shipping) in which the group appears, then by
component order in the rule. Non-tax groups (`exempt`, `nil`, `outsideScope`) have `component: null` and `tax: 0`.

### Step 8: totals
- `taxable = Σ taxable_i` (lines + shipping); `tax = Σ charged tax`; `taxNotCharged = Σ tax with charged:false`.
- If `config.rounding.grandTotal` exists and `draft.roundOff ?? grandTotal.defaultOn`:
  `rounded = round((taxable + tax) / roundToMinor, grandTotal.mode) × roundToMinor`,
  `roundOff = rounded − (taxable + tax)`; otherwise `roundOff = 0`.
- `total = taxable + tax + roundOff`.
- Identities (checked by `make validate-spec`): exclusive → `subtotal − discount + shipping = taxable`;
  inclusive → `subtotal − discount + shipping = taxable + tax`; always `total = taxable + tax + roundOff`.

### Step 9: home currency
When `foreignCurrency`, `config.foreignCurrency.homeTotals` and `draft.exchangeRate` are all present:
`conv(x) = round(x × exchangeRate × 10^(homeExp − docExp), amountMode)` and
`home = { currency, rate, taxable: conv(taxable), tax: conv(tax), total: conv(total) }`; when
`taxInHomeCurrency`, each tax line also gets `homeTax = conv(tax)`. Otherwise `home = null`.
`exchangeRate` = units of home currency per 1 unit of document currency.

### Step 10: notes
`reg.notes`, then the matched rule's `notes` (only when `chargesTax`), then `reverseCharge.notes` (only when
`reverseCharge`). Duplicates removed, order kept. Output `{ id, text, placement }` from `notesCatalog`.

### Step 11: title
`quote` → `titles.quote`. `invoice` → `titles.invoiceAllExempt` when present, `chargesTax`, and every line
(shipping ignored) is a non-tax group of category `exempt` or `nil`; otherwise `titles.invoice`.

### Step 12: checks → issues
Evaluate `config.checks` in order; each produces at most one issue `{ code, severity, lines? }`.
- `when` keys: `supplyType`, `sameRegion`, `sellerRegistration`, `buyerIsBusiness`, `buyerHasTaxId`,
  `reverseCharge`, `docType`, `foreignCurrency`, and `totalAtLeastMinor` (compared with `total` when not foreign,
  otherwise with `home.total`; false when neither is available).
- `require` (default type): the issue fires when the check's `when` matches and any listed field is empty
  (missing, or only whitespace).
- `productCodeDigits`: when `seller.turnoverMinor` is unknown, use the first tier; otherwise the first tier that
  either has no `maxTurnoverMinor` (an open-ended tier) or has `maxTurnoverMinor ≥ seller.turnoverMinor`. Required
  digits = `b2bDigits` if the buyer has a tax ID, else `b2cDigits`. Lines (not shipping) whose `productCode` has
  fewer digits than required are listed in `lines` (0-based indexes, ascending).
- **Order of `issues`:** the Step 2 `rate_not_effective` issue first (if any), then config checks in config order.
  Fixtures compare `issues` as an ordered array.
- Issues with severity `error` block issuing the document; drafts and previews still compute.

**Errors vs issues.** `no_component_rule`, `unknown_rate`, `discount_exceeds_subtotal` and
`inclusive_compound_unsupported` are *errors*: computation stops and no `ComputedDocument` is returned (the builder
shows the problem inline). Everything in `issues` is computed alongside a complete result.

## 4. Output

```
ComputedDocument {
  title, chargesTax, placeOfSupply?, sameRegion?, reverseCharge, inclusive,
  lines:    [{ amount, discount, taxable, rateId, rate, category, taxes?: [{ component, rate, amount }] }],
  shipping: { amount, taxable, parts: [{ rateId, amount, taxable }] } | null,
  taxLines: [{ component | null, rate, category, taxable, tax, charged, homeTax? }],
  totals:   { subtotal, discount, shipping, taxable, tax, taxNotCharged, roundOff, total },
  home:     { currency, rate, taxable, tax, total } | null,
  notes:    [{ id, text, placement }],
  issues:   [{ code, severity, lines? }]
}
```
`lines[i].discount` is the invoice-discount share allocated to the line. `taxes` appear only for
`taxLevel = line`. Rates are output as canonical decimal strings (Section 7.2).

## 5. Numbering

Pattern tokens: `{seq:N}` (sequence zero-padded to at least N digits, never truncated), `{fy}` (fiscal year
`YY-YY`, e.g. `26-27`), `{fyLong}` (`YYYY-YY`), `{yyyy}`, `{yy}`, `{mm}`; all other characters are literal.
- The fiscal year containing date `d` starts in `d.year` if `(d.month, d.day) ≥ fiscalYearStart`, else in `d.year − 1`.
- Period key for sequence counters: `reset = never` → `all`; `fiscalYear` → `FY<start year>`; `calendarYear` → `CY<year>`.
  A new period key starts the sequence at 1.
- Result checks: longer than `numbering.maxLength` → error `number_too_long`; not matching `allowedPattern` →
  error `number_invalid_chars`.
- Numbers are allocated only at issue, from a series owned by the issuing device (ADR-0015).

## 6. Document status (derived, never stored)

Invoice, first match wins: `void` (lifecycle void) · `draft` (lifecycle draft) · `paid` (paid ≥ total) ·
`overdue` (dueDate set and today > dueDate) · `partiallyPaid` (paid > 0) · `sent` (sentAt set) · `issued`.
Quote: `void` · `draft` · `converted` / `accepted` / `declined` (stored outcome) · `expired` (validUntil set and
today > validUntil) · `sent` · `open`. `outstanding = max(total − paid, 0)` for invoices.

## 7. Formatting

### 7.1 Money
`formatMoney(minor, currency, homeCurrency)`:
- Digits of `|minor|`, left-padded to `exp + 1`; the last `exp` digits are the fraction (omitted when `exp = 0`).
- Group the integer part from the right: first group size `grouping[0]`, then the last element of `grouping`
  repeatedly (INR `[3,2]` → `1,23,45,678`; others `[3]` → `12,345,678`). Group separator `,`, decimal `.`.
- Prefix: the currency `symbol` when `currency == homeCurrency`, otherwise the ISO code plus a space (`USD 1,234.50`).
- Negative values: `-` before the prefix (`-₹1,234.00`).

### 7.2 Rates and quantities
Canonical decimal string: drop trailing fractional zeros and a trailing `.` (`"18.00"` → `18`, `"8.8750"` → `8.875`).
Percent display appends `%`.

### 7.3 Amount in words
`{wordsMajor} {words(major)}[ and {words(minor)} {wordsMinor}] Only` — the minor part appears only when non-zero and
the currency has minor units. Words are Title Case, joined by single spaces, with no "and" or hyphens inside numbers:
`Zero`, `One`…`Nineteen`, `Twenty`…`Ninety` (+ unit: `Twenty One`), `Hundred`.
- INR uses the Indian system: `Crore` (10^7), `Lakh` (10^5), `Thousand`, `Hundred`; values ≥ 100 crore recurse
  (`One Hundred Crore`).
- All other currencies use the international system: `Billion`, `Million`, `Thousand`, `Hundred`.
- Example: 12055025 paise → `Indian Rupees One Lakh Twenty Thousand Five Hundred Fifty and Twenty Five Paise Only`.

## 8. Tax ID validation

Normalise first: trim, remove all whitespace, uppercase. Output `{ valid, normalized, region?, error? }` with
`error ∈ { format, checksum, unknown_region }`.
- `gstinMod36`: characters `0-9A-Z` map to 0–35; for the first 14 characters, weight 1 at even (0-based) positions
  and 2 at odd positions; `p = value × weight`; `sum += p div 36 + p mod 36`; check = `(36 − sum mod 36) mod 36`
  must equal the 15th character. `region` = first 2 characters, which must be a region code in the config.
- `ukVatMod97`: if the input is 9 or 12 digits without prefix, prepend `normalizePrefix`. For numeric forms,
  take the first 9 digits `d0…d8`: `w = Σ d_i × (8,7,6,5,4,3,2)` for i = 0…6, `chk = 10 × d7 + d8`; valid if
  `(w + chk) mod 97 = 0` or `(w + 55 + chk) mod 97 = 0`. `GD`/`HA` forms are format-checked only.

## 9. UPI payment link (India, PDF QR code)
`upi://pay?pa=<vpa>&pn=<payee name>&am=<amount>&cu=INR&tn=<invoice number>` — `am` is the outstanding amount with
exactly two decimals and no grouping (`1234.50`); each value is percent-encoded as UTF-8, leaving only RFC 3986
unreserved characters (`A–Z a–z 0–9 - . _ ~`) and `@` unencoded (space → `%20`, `/` → `%2F`, `&` → `%26`).
Only for INR documents with a UPI ID and an outstanding amount > 0.

## 10. Out of scope for v0
SEZ supplies, compensation cess, TDS/TCS, negative amounts (credit notes), compound taxes with inclusive prices,
e-invoicing (IRN/QR). Each needs spec + fixtures before implementation.
