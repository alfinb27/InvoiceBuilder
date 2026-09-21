# UK VAT — invoice rules used by the app

- **Last verified:** 2026-09-19 (desk research; not legal advice)
- **Professional review:** pending — a UK accountant must confirm the open questions below and the fixtures in
  `spec/fixtures/tax/gb.json` before Phase 2a is signed off.
- **Implements:** `spec/tax/GB.json`, `spec/tax/ENGINE.md`

## Sources

| Topic | Source (opened) | Notes |
|---|---|---|
| Full / simplified / modified VAT invoices | [VAT Notice 700/21 Record keeping](https://www.gov.uk/guidance/record-keeping-for-vat-notice-70021) (updated 18 March 2024) | Full invoice particulars; simplified invoices up to £250; VAT total must be in sterling |
| Rounding on invoices | [VAT Notice 700](https://www.gov.uk/guidance/vat-guide-notice-700) para 17.5 (page updated 25 June 2026); [VATREC12010](https://www.gov.uk/hmrc-internal-manuals/vat-trader-records/vatrec12010) (updated 16 January 2025); [VATREC12030](https://www.gov.uk/hmrc-internal-manuals/vat-trader-records/vatrec12030) | Total VAT payable may be rounded down to a whole penny; line level: round down to 0.1p or to nearest 1p/0.5p |
| Domestic reverse charge (construction) | [VAT domestic reverse charge technical guide](https://www.gov.uk/guidance/vat-reverse-charge-technical-guide), [VATREVCON37100](https://www.gov.uk/hmrc-internal-manuals/vat-reverse-charge-for-building-and-construction-services-manual/vatrevcon37100) | Invoice must make clear the reverse charge applies and reference "reverse charge"; wording not prescribed |
| Non-VAT invoices | [Invoices: what they must include](https://www.gov.uk/invoicing-and-taking-payment-from-customers/invoices-what-they-must-include) | Unique number, business details, customer, description, date of supply and issue, amounts |
| VAT number check digits | [Wikipedia: VAT identification number](https://en.wikipedia.org/wiki/VAT_identification_number), [AccountingWEB thread](https://www.accountingweb.co.uk/any-answers/vat-algorithm) | Mod 97 and 9755 variants; verified on GB980780684 |

## Rules and where they live

| Rule | App behaviour | Where |
|---|---|---|
| Sequential number based on one or more series, uniquely identifying the document | Numbering (`INV-{seq:4}`, no reset); device-owned series with sync | `GB.json` numbering, ADR-0015 |
| Time of supply (tax point) and date of issue | `supplyDate` (optional, defaults to issue date) and `issueDate` | ENGINE §3 |
| Supplier name, address, VAT number | `seller_tax_id_missing` blocks VAT invoices without a VAT number | `GB.json` checks |
| Customer name and address | `buyer_details_required` warning | `GB.json` checks |
| Per line: description, quantity, rate of VAT, amount excluding VAT; unit price | Line model + template columns | PDF templates |
| Total excluding VAT, total VAT in sterling | Totals; `taxInHomeCurrency` converts VAT to GBP for foreign-currency invoices; issuing blocked without an exchange rate | `GB.json` foreignCurrency, checks |
| Rounding | Invoice-level VAT per component rounded down (toward zero); groups split by largest remainder | `GB.json` rounding, ENGINE §3 Step 6 |
| Zero-rated / exempt shown separately | Separate tax lines by category (`zero`, `exempt`, `outsideScope`) | ENGINE §3 Step 7 |
| Domestic reverse charge | VAT shown as the customer's liability, not charged; note "Reverse charge: customer to account for the VAT to HMRC" | `GB.json` reverseCharge |
| B2B services to overseas customers | "Outside the scope of UK VAT" | `GB.json` componentRules |
| Not VAT registered | Plain "Invoice", no VAT | `GB.json` registrations |

## Open questions for the accountant

1. Invoice-level rounding down of the total VAT, then splitting it across rates by largest remainder for display — acceptable?
2. VAT-inclusive pricing: VAT = inclusive × rate/(100 + rate) rounded down, net = inclusive − VAT — acceptable?
3. Title "VAT Invoice" for registered businesses — fine, or prefer "Tax Invoice"/"Invoice"?
4. Reverse-charge wording and showing the VAT amount the customer must account for — adequate?
5. Services to overseas business customers: is "Outside the scope of UK VAT" enough, or should EU/overseas customers see a reverse-charge note for their own VAT?
6. Exchange rates for foreign-currency invoices: we use a user-entered rate. Should the app suggest HMRC period rates or record the rate source?
7. We always issue full VAT invoices (never simplified). Any downside for small retail sales?
8. Delivery charges on mixed-rate invoices are apportioned by value across rates — acceptable default?

Added in Phase 2 (`spec/documents.md`, fixtures `spec/fixtures/tax/gb-combinations.json`, `errors.json`):

9. A new invoice for an overseas **business** client defaults to "Services to an overseas business" (outside the
   scope); overseas consumers stay UK supplies. Right defaults, given goods exports need "Goods exported"?
10. Issuing is blocked while a foreign-currency invoice has no exchange rate (VAT must also be shown in sterling).
    Should the rate instead default to something (e.g. HMRC's monthly rate) with a warning?
11. Invoice numbers come from a series per device (e.g. `INV-0001` on the iPhone, `INV-B0001` on an iPad), allocated
    only at issue and never reused. Does "a sequential number based on one or more series" cover this?

Added in Phase 3 (`spec/pdf/RENDERING.md`, samples from `make pdf-samples`):

12. On a foreign-currency invoice the VAT summary gains a sterling column and the totals show the sterling
    equivalent with the rate used. Does that meet "VAT payable in sterling" for a euro invoice?
13. With VAT rounded per invoice, the line rows carry no VAT column and the per-rate summary does the work. Is that
    layout acceptable for a full VAT invoice?
14. The domestic reverse charge note reads "Reverse charge: customer to account for VAT to HMRC" with the VAT
    amount shown but not charged. Is the wording and the presentation right?
