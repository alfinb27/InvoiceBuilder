# India GST — invoice rules used by the app

- **Last verified:** 2026-09-19 (desk research; not legal advice)
- **Professional review:** pending — a Chartered Accountant must confirm the open questions below and the fixtures in
  `spec/fixtures/tax/in-*.json` before Phase 2a is signed off.
- **Implements:** `spec/tax/IN.json` (configVersion 2025-09-22), `spec/tax/ENGINE.md`

## Sources

| Topic | Source (opened) | Notes |
|---|---|---|
| Tax invoice particulars — CGST Rule 46 | [CBIC Rule 46](https://taxinformation.cbic.gov.in/content/html/tax_repository/gst/rules/cgst_rules/active/chapter6/rule46_v1.00.html) (TLS error when fetched); text cross-checked at [GSTZen Rule 46](https://gstzen.in/a/tax-invoice-cgst-rule-46.html) | Clauses (a)–(s) and provisos |
| Bill of supply — CGST Rule 49 | [GSTZen Rule 49](https://gstzen.in/a/bill-of-supply-cgst-rule-49.html) | Composition dealers and exempt supplies |
| Composition declaration — CGST Rule 5 | [CBIC Rule 5](https://taxinformation.cbic.gov.in/content/html/tax_repository/gst/rules/cgst_rules/active/chapter2/rule5_v1.00.html) | "composition taxable person, not eligible to collect tax on supplies" at the top of the bill of supply |
| GST rate rationalisation from 2025-09-22 | [TaxGuru: Notification 9/2025-CT(Rate)](https://taxguru.in/goods-and-service-tax/notification-9-2025-ctrate-complete-hsn-wise-gst-rate-chart-effective-22nd-sept-2025.html), [SCC Online summary](https://www.scconline.com/blog/post/2025/09/18/new-gst-rates-notifed-wef-22-september/) | 12% and 28% slabs largely removed; 5% and 18% main slabs; 40% for luxury/sin goods |
| GSTIN check character | [DEV: GSTIN checksum](https://dev.to/tarun_vaghasia_a387e1ac9b/how-gstin-checksum-validation-works-and-why-it-isnt-enough-3l8e) | Algorithm reproduced and verified on 3 real GSTINs (`spec/fixtures/validation/tax-ids.json`) |
| UPI payment links | [NPCI UPI Linking Specifications 1.6](https://www.labnol.org/files/linking.pdf) (mirror) | `upi://pay?pa=&pn=&am=&cu=INR&tn=` |

## Rules and where they live

| Rule (Rule 46 unless stated) | App behaviour | Where |
|---|---|---|
| (a) Supplier name, address, GSTIN | Business profile; `seller_tax_id_missing` blocks issuing for regular/composition dealers | `IN.json` checks |
| (b) Consecutive serial number ≤ 16 chars, letters/digits/`-`/`/`, unique per financial year, one or multiple series | Numbering: `maxLength 16`, `allowedPattern`, `reset: fiscalYear`; device-owned series with sync | `IN.json` numbering, ENGINE §5, ADR-0015 |
| (c) Date of issue | `issueDate`; optional `supplyDate` selects rates | ENGINE §3 Step 0 |
| (d) Recipient name, address, GSTIN if registered | Client record; `buyer_address_missing` warning for B2B | `IN.json` checks |
| (e) Unregistered recipient, value ≥ ₹50,000: name, address, delivery address, state name and code | `buyer_details_required` (domestic only, total ≥ 5,000,000 paise) | `IN.json` checks |
| (g) HSN/SAC code | `product_code_missing` with digits by turnover tier (4 for B2B up to ₹5 crore, 6 above) | `IN.json` productCodes |
| (h)–(m) Description, quantity + unit (UQC), total value, taxable value after discount, rates and amounts per component | Line model, UQC units, CGST/SGST/UTGST/IGST tax lines | ENGINE §3 |
| (n) Place of supply + state name for inter-state supplies | `placeOfSupply` derived from buyer state (`96` for exports), overridable | ENGINE §3 Step 0 |
| (p) Whether tax is payable on reverse charge | RCM: tax shown, not charged, note `rcm` | `IN.json` reverseCharge |
| (q) Signature or digital signature | Signature image + "Authorised signatory" on every template | PDF labels |
| Export endorsement | `SUPPLY MEANT FOR EXPORT UNDER BOND OR LETTER OF UNDERTAKING WITHOUT PAYMENT OF INTEGRATED TAX` / `…ON PAYMENT OF INTEGRATED TAX` | `IN.json` notesCatalog |
| Intra-state in a UT without legislature | CGST + UTGST (Chandigarh, Lakshadweep, A&N Islands, DNH&DD, Ladakh) | `IN.json` regions |
| Composition dealers | Bill of Supply, no tax, declaration at the top | `IN.json` registrations |
| Exempt-only supplies by a regular dealer | Bill of Supply title | `IN.json` titles.invoiceAllExempt |

## Open questions for the CA

1. Is rounding the grand total to the nearest rupee (a "Round off" line, half away from zero) acceptable on tax invoices?
2. Line-level rounding of each CGST/SGST amount (half away from zero), so CGST always equals SGST — acceptable?
3. Tax-inclusive prices: each component = inclusive × component rate / (100 + total rate), taxable = inclusive − taxes. Acceptable?
4. Shipping charged by the supplier taxed at the rate of the highest-value line (composite supply, principal supply) — acceptable default?
5. HSN digits: 4 digits mandatory for B2B up to ₹5 crore turnover, optional for B2C; 6 digits above ₹5 crore (Notification 78/2020-CT, not yet opened) — confirm current position.
6. Exports under LUT: show IGST at 0% (zero-rated) plus the endorsement and LUT ARN — confirm presentation.
7. Reverse charge: should the supplier's invoice show the tax amounts payable by the recipient (we do, marked "not charged")?
8. Status of the 28% rate after 2025-09-22 (kept in config with a warning note) and whether any v1 users need compensation cess (out of scope).
9. Place-of-supply code `97` (Other Territory): UTGST treatment correct?
10. Mixed taxable + exempt supplies to unregistered buyers: we title it "Tax Invoice"; should it be an invoice-cum-bill of supply (Rule 46A)?
