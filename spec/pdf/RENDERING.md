# PDF rendering (v0)

Normative for `InvoicePDF` (iOS) and `:core:pdf` (Android). A PDF is drawn natively from two inputs (ADR-0006):

1. a **view model** — every string already formatted, built by a pure function from the stored document
   (`documents.md`), its `ComputedDocument` (`tax/ENGINE.md` §4), the tax config and `pdf/labels/en.json`;
2. a **template** — `pdf/layout/<templateId>.json`, block order and style tokens as data.

The view model is proven by `fixtures/pdf/*.json` (kind `pdf`): both platforms build the same strings from the same
document. The drawing itself is checked per platform by extracting the text back out of the rendered PDF and by
image snapshots.

## 1. View model

`PDFDocumentModel` (same names on both platforms):

```
PDFDocumentModel {
  title, isDraft, draftLabel?, number?, numberLabel, meta: [Field], seller: Party, buyer: Party?, shipTo: Party?,
  columns: [Column], rows: [[String]], totals: [TotalRow], taxSummary: Table?, amountInWords?,
  homeTotals?, notes: [Note], payment: Payment, signature: Signature, footer: Footer
}
Field  { label, value }
Party  { heading?, name, lines: [String], fields: [Field] }
Column { id, label, align: "leading" | "trailing" }
Table  { columns: [Column], rows: [[String]] }
TotalRow { label, value, emphasis: "normal" | "strong" }
Note   { label?, text, placement: "top" | "bottom" }
Payment { bank: [Field], upi?: { id, caption, payload } }
Signature { imageAssetId?, forBusiness, authorisedSignatory }
Footer { pageLabel, continued }   // the label strings; the renderer fills {page} and {pages}
```

- **title** = `computed.title` ("Tax Invoice", "Bill of Supply", "VAT Invoice", "Quotation", …).
  **isDraft** = the document has no number; every page then carries **draftLabel** (the `draft` label) as a
  watermark.
- **number / numberLabel**: `document.number` with `invoiceNumber` or `quoteNumber`.
- **meta**, in order and only when set: `issueDate`, `supplyDate`, `dueDate` (invoices) or `validUntil` (quotes),
  `placeOfSupply` (`computed.placeOfSupply`, shown as the region's name when the config knows it).
- **seller** from `sellerSnapshot`: `name`; `lines` = `legalName` when it differs, the postal address (line 1,
  line 2, city with postcode, the region's name, the country's name when it is not the business's own), then
  `email`, `phone` and `website`; `fields` = `taxId` (labelled with the config's `taxIdName`), `pan`,
  `companyNumber`, `registeredOffice` and `lutReference`, each only when set.
- **buyer** from `buyerSnapshot` under the `billTo` heading, with the same address rules; its `fields` hold only
  the tax ID, labelled with the config's `taxIdName` for a buyer in the business's own country and `foreignTaxId`
  otherwise. Omitted when the document has no client. **shipTo** appears under the `shipTo` heading only when the
  client's shipping address differs from the billing one.
- **notes**, in this order: the engine's `placement: "top"` notes, the document's own `notes` and `terms` (labelled
  `notes` / `terms`, placement `bottom`), then the engine's `placement: "bottom"` notes.

### 1.1 Items table columns
In this order, each included only when the rule holds:

| Column | Included when | Cell |
|---|---|---|
| `index` | always | 1-based row number |
| `description` | always | the line description |
| `productCode` | any line has one | the code; label = the config's `productCodeName` |
| `quantity` | always | `SpecFormatter.quantity` |
| `unit` | any line has one | the unit's code (UQC), e.g. `KGS`, `JOB` — India requires the UQC on the invoice |
| `unitPrice` | always | money; the label gets "(incl. …)" when the document is tax-inclusive (§1.4) |
| `discount` | any line has a line discount | percent (`10%`) or money |
| `taxable` | the seller charges tax | `computed.lines[i].taxable` |
| one per tax component | the config rounds tax **per line**, the seller charges tax, and at most two component codes appear | that line's component tax; the header is the code plus the rate when every line shares it (`CGST 9%`), else the code |
| `amount` | always | tax per line: `taxable + line tax`; otherwise `taxable` (the tax summary then carries the tax) |

A non-tax line (exempt, nil-rated, outside the scope) shows its category name in the component columns.

### 1.2 Totals
In order: `subtotal`; `invoiceDiscount` (negative) and `shipping` when they are not zero; `taxableValue` when the
seller charges tax; one row per **component code** among the charged tax lines, in order of first appearance,
summing that component's tax — labelled with the code plus the rate when all its tax lines share one rate
(`CGST 9%`), otherwise the code alone (`CGST`); `roundOff` when it is not zero; then `total` with
`emphasis: "strong"`. Non-tax groups (exempt, nil, outside the scope) carry no amount, so they appear in the tax
summary, not here, and the per-rate split always stays visible in that summary. Phase 4 adds `amountPaid` and
`balanceDue`.

- **taxSummary** (when the seller charges tax and either there is more than one tax line or tax is rounded per
  invoice): columns `{taxName} rate`, `taxableValue`, `{taxName}`; one row per tax line — a non-tax group is named
  by its category (`Exempt`, `Nil rated`, `Zero-rated`, `Outside the scope`) with an empty tax cell — and a last
  row `totalTax`. With `taxInHomeCurrency` (UK VAT on a foreign-currency invoice) a `taxAmountInCurrency` column
  is added.
- **amountInWords** when `config.amountInWords`: `ENGINE.md` §7.3 of the total, in the document currency.
- **homeTotals** when `computed.home` exists: `homeCurrencyEquivalent` with the rate, then the home total.
- **reverse charge**: when `totals.taxNotCharged > 0`, the `taxNotChargedRecipient` line appears under the totals.

### 1.3 Payment and signature
- `payment.bank`: the seller snapshot's bank fields that are set, labelled (`accountName`, `accountNumber`,
  `bankName`, `ifsc`, `sortCode`, `iban`, `swift`).
- `payment.upi`: for INR documents with a UPI ID and an outstanding amount (`ENGINE.md` §9) — the id, the
  `upiScanToPay` caption and the `upi://pay` payload for the QR code.
- `signature`: the signature image (when the business has one), `forBusiness` with the business name and
  `authorisedSignatory` underneath.

### 1.4 Formatting
- Money: `ENGINE.md` §7.1 — the symbol for the business's home currency, the ISO code for any other.
- Quantities and percents: §7.2. Dates: day without a leading zero, the English month abbreviation and the year
  (`19 Sep 2026`, `9 Oct 2026`) — the same on every device and locale.
- Tax-inclusive documents: the `unitPrice` label becomes `unitPriceInclusive` and the `amount` column stays
  `taxable + tax`, so `quantity × unitPrice = amount` on the page.

## 2. Template layout

`pdf/layout/<id>.json` (`schema/pdf-layout.schema.json`), one per `templateId`: `classic`, `modern`, `minimal`,
`compact`. A template lists **blocks** in drawing order and **style tokens**; it never contains text (that is the
view model's job) and never contains rules (that is this document).

- `page.margins`, `page.footerHeight` in points; the page size comes from `config.paperSize` (A4 595 × 842 pt,
  Letter 612 × 792 pt).
- `style`: font sizes (`title`, `heading`, `body`, `small`), line height factors, rule width and colour, table
  header fill, row spacing, and whether the accent colour (the business's, else the first token preset) is used for
  the title, the table header or a header band.
- `blocks`: `header`, `parties`, `items`, `totals`, `payment`, `notes`, `signature`. Each has a `variant` the
  renderer understands (e.g. `header.logoLeft` / `logoRight` / `band`), and blocks may be omitted by a template.

## 3. Pagination

1. Draw the header block on page 1; on later pages draw a short repeat (title, number, page label).
2. The items table repeats its column header on every page. A row is never split; a row that does not fit starts
   the next page. When the table continues, the page ends with the `continued` label.
3. The totals block (totals, tax summary, amount in words, home totals) is kept whole: if it does not fit under the
   last row, it moves to the next page. The tax summary sits *beside* the totals — summary left, totals right,
   both starting at the same line — whenever the summary still gets a readable width (at least 170 pt); otherwise
   it goes above them. The block ends below whichever column is taller.
4. Payment, notes and signature are one closing region and stay on the same page: a page holding nothing but a
   note and a signature line reads as a mistake. If the region does not fit, all of it moves to the next page.
   When it misses the bottom by a little, the QR shrinks first — to no less than 56 pt, about 2 cm printed, which
   every UPI app still scans. Below that the region moves at its full size.
5. Every page carries the footer `page` label ("Page 1 of 3"), so the renderer lays out twice: once to count pages,
   once to draw.
6. A draft (no number) also carries the `draft` watermark on every page.

## 4. Fonts, images and size

- Text is drawn with the bundled static Noto Sans (Regular / SemiBold / Bold) and Noto Sans Devanagari for
  Devanagari runs (`pdf/fonts/`, OFL). Variable fonts are not used (they broke text extraction in the spike).
- Every string must be selectable and searchable in the output, including `₹`, `£` and Devanagari. Devanagari is
  drawn with the bundled font and embedded, but a PDF stores glyphs in visual order, so extracting text that
  contains a pre-base vowel sign (`वि`) can reorder that cluster. That is a limit of the format, not of the
  renderer; the rendered page is correct, and words without pre-base signs extract exactly.
- The logo is drawn inside the header box, scaled to fit without distortion; the signature above the
  `authorisedSignatory` line. Both come from `asset` rows.
- The UPI QR is generated from the payload in §1.3 with error correction level M.
- A one-page invoice must stay under 300 KB with the fonts subset.

## 5. Caching

A rendered PDF is cached per `(document.id, revision, templateId, taxConfigRef, accent colour, logo/signature asset
ids)`. Issued documents never change, so their cache entry is permanent; a draft's entry is replaced whenever the
draft is saved. The cache is a file in the app's caches directory and is never backed up.
