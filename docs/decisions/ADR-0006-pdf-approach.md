# ADR-0006: PDF generation approach

- **Status:** Accepted — Option B, from the Phase 0 desk spike (`docs/spikes/pdf-spike.md`); device checks listed there
- **Date:** 2026-09-19

## Options considered
- **A. Shared HTML/CSS templates** + one shared `render.js` filling the DOM from a JSON view model.
  iOS: off-screen `WKWebView` → `UIPrintPageRenderer` + `viewPrintFormatter()` → `UIGraphicsPDFRenderer`.
  Android: off-screen `WebView` → `createPrintDocumentAdapter()` → file (silent export needs a helper class in the
  `android.print` package to reach package-private callbacks — the main risk).
- **B. Native drawing from a shared JSON layout spec.** iOS: `UIGraphicsPDFRenderer` + Core Text.
  Android: `PdfDocument` + `Canvas` + `StaticLayout`. Pagination written by hand on both.
- Rejected: per-platform PDF libraries (output drifts; iText is AGPL); shared Typst/Rust engine (10–20 MB + FFI).

## Rubric (weights)
Visual parity 25 · Pagination (60 lines, repeated header, totals kept whole, "Page x of y") 20 ·
Effort for 4 templates × 2 platforms 20 · Robustness (no private-API workarounds) 15 ·
Speed/memory on a ≤3 GB RAM Android 10 · Selectable text, file < 300 KB 10.

## Prior
A, unless silent Android export fails on any test API level (26 / 30 / 35–36) or takes > 2 s on the low-end
device; then B with templates in `spec/pdf/layout/`. If still tied after scoring, choose B.

## Decision
**Option B: native drawing from a shared, declarative layout spec** (`spec/pdf/layout/`), rendered by Core Text in
`UIGraphicsPDFRenderer` on iOS and `PdfDocument` + `StaticLayout` on Android. Rubric score B 83 vs A 60.

Deciding evidence (desk spike, macOS):
- WebKit's PDF output dropped Devanagari glyphs (print and `createPDF` paths) while its on-screen layout rendered them;
  Chromium and Core Text rendered and kept them searchable. Indian users type Hindi names and descriptions.
- WebKit printing did not repeat the table header on later pages and ignores CSS page-margin boxes (no "Page x of y").
- Option A's Android path still needs a package-private print workaround.

## Consequences
- Templates are data: blocks + style tokens shared in the spec; one renderer per platform; parity via text-extraction
  fixtures and snapshots. Phase 3 +2–3 dev-days, Phase 7b +2 dev-days.
- Bundle **static** font files (Noto Sans + Noto Sans Devanagari, Regular/SemiBold/Bold, OFL); variable fonts produced
  Type 3 embedding (Chromium) and lost Unicode mappings (WebKit).

## Revisit when
The device checks in the spike report fail (e.g. Android `StaticLayout` too slow on a low-end phone), or template
authoring cost in Phase 3 exceeds the estimate by more than 50%.
