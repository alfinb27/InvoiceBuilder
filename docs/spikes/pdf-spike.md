# PDF spike: HTML templates (A) vs native drawing (B)

- **Date:** 2026-09-19 · **Decision:** ADR-0006 → **Option B (native drawing from a shared layout spec)**
- **Scope run:** a desk spike on macOS. Chromium (Blink, the engine inside Android WebView) and macOS WebKit (the engine
  inside WKWebView) rendered the same HTML template; a Core Text prototype rendered the same data natively.
- **Not yet run:** iOS device (needs Xcode) and Android devices API 26/30/36 + a low-end phone (needs Android Studio).
  The remaining device checks are listed at the end; none of them is expected to reverse the decision.

## Test documents

View models generated from `spec/fixtures` (`spikes/pdf/viewmodels/`): a one-line UK VAT invoice; a 60-line GST
invoice with long descriptions; a USD export under LUT; a GST invoice with Devanagari client name and descriptions.

## Results

| Check | A · Chromium (≈ Android WebView) | A · macOS WebKit (≈ iOS WKWebView) | B · Core Text (≈ iOS native) |
|---|---|---|---|
| 60-line invoice pagination | 4 pages, rows never split, totals block kept whole | 4 pages, rows never split | 4 pages, rows never split, totals kept whole |
| Table header repeated on every page | ✓ (`thead` repeats) | ✗ header only on page 1 | ✓ (drawn per page) |
| "Page x of y" | ✓ CSS `@page` margin boxes | ✗ margin boxes unsupported | ✓ (two-pass layout) |
| Devanagari (Hindi client name, descriptions) | ✓ rendered and searchable | **✗ glyphs missing from the PDF** (print *and* `createPDF` paths), although on-screen layout renders them | ✓ rendered and searchable |
| ₹ / £ / hyphens in numbers searchable | ✓ | ✓ with static fonts (✗ with variable fonts) | ✓ |
| File size (static Noto fonts) | 33–50 KB | 31–60 KB | 25–45 KB |
| Time per document (desktop Mac) | 10–75 ms | ~130–170 ms + WebView load | 3–60 ms |
| Code for one template | 200 lines (HTML/CSS/JS) shared by both platforms | same | 160 lines Swift for one platform, plus the Android equivalent |

Evidence: `docs/spikes/pdf/*.pdf` (60-line and Devanagari documents from each engine) and
`vm-04-webkit-snapshot.png` (WebKit's on-screen rendering of the page whose PDF lost the Hindi text).

### Other findings
1. **Use static font files, not variable fonts.** With variable Inter/Noto, Chromium embedded Type 3 fonts (200–280 KB
   files) and WebKit lost the Unicode mapping for ₹ and hyphens. Static Noto Sans + Noto Sans Devanagari
   (Regular/SemiBold/Bold, OFL) fixed both. This applies to either option.
2. The Android-specific risk of Option A (silent WebView → PDF needs a helper class in the `android.print` package
   to reach package-private callbacks) was not reached; it would only add to A's cost.
3. B needs every layout rule hand-written; the prototype shipped two layout bugs on its first run (a fixed-height
   header box and a too-narrow index column). A shared, declarative layout spec plus snapshot tests is the mitigation.

## Rubric (ADR-0006 weights; scores 1–5 from the evidence above)

| Criterion | Weight | A | B |
|---|---|---|---|
| Visual parity across platforms | 25 | 3 (engines differ in headers, page numbers, scripts) | 4 (same fonts and layout spec; snapshot tests) |
| Pagination | 20 | 2 (WebKit: no repeated header, no page numbers) | 5 |
| Effort, 4 templates × 2 platforms | 20 | 5 | 2 |
| Robustness, no workarounds | 15 | 1 (WebKit drops Devanagari; Android print workaround) | 5 |
| Speed and memory | 10 | 4 | 5 |
| Selectable text, small files | 10 | 3 (Devanagari lost on WebKit) | 5 |
| **Weighted total (out of 100)** | | **60** | **83** |

## Decision and plan impact

**Option B.** Templates are defined once in `spec/pdf/layout/` as data (blocks: header, parties, items table,
totals, tax summary, payment/UPI, notes, signature, footer; plus style tokens), and each platform has one renderer:
Core Text in `UIGraphicsPDFRenderer` (iOS) and `PdfDocument` + `StaticLayout` (Android). The four templates become
style/arrangement variants of the same blocks. Parity is enforced by text-extraction fixtures and image snapshots.

- Phase 3 (iOS) grows by about 2–3 dev-days (layout spec + renderer instead of CSS); Phase 7b (Android) by about 2.
- The spike's HTML template remains a visual reference for the templates' design.

## Device checks still to run (Phase 1 / Phase 3 start)
1. Android: port `spikes/pdf/native` to `PdfDocument` + `StaticLayout`; time the 60-line invoice on a ≤3 GB RAM
   phone (target < 2 s) and check Devanagari shaping and text extraction on API 26, 30 and 36.
2. iOS: run the Core Text renderer inside `UIGraphicsPDFRenderer` on a device (expected identical to macOS).
3. Optional, only to revisit A: confirm whether iOS WKWebView also drops Devanagari glyphs in PDF output.
