# Phase 3 status (PDF generation, templates, UPI QR, sharing)

- **As of:** 2026-09-21
- **Summary:** documents render to PDF natively from a spec'd view model and four JSON templates. The preview
  screen, the template switcher, share, AirPrint, Save to Files and the "Mark as sent?" prompt work on iPhone and
  iPad, and on a wide iPad the builder draws the draft live beside the form. Outstanding: the TestFlight round with
  real businesses, the professional check of the four sample documents, and per-template image snapshots.

## Tasks (plan § Phase 3)

| # | Task | Status | Evidence |
|---|---|---|---|
| 1 | PDF view-model builder (`ComputedDocument` + snapshots → strings, labels from `spec/pdf/labels/en.json`) | ✅ | `InvoiceCore/PDF/PDFModelBuilder.swift`; 9 `pdf` fixtures |
| 2 | The renderer from the spike (ADR-0006) and four templates with an accent colour | ✅ | `InvoicePDF` (Core Text + `UIGraphicsPDFRenderer`); `spec/pdf/layout/{classic,modern,minimal,compact}.json` |
| 3 | Pagination rules, fonts, UPI QR | ✅ | `RENDERING.md` §3–4; bundled Noto with a Devanagari cascade; `CIQRCodeGenerator` |
| 4 | Preview screen (PDFKit) with a template switcher | ✅ | `InvoiceUI/Documents/DocumentPreviewView.swift` |
| 5 | Share, print, save to Files, "Mark as sent?" | ✅ | `UIActivityViewController` (Save to Files is in the sheet), `UIPrintInteractionController`, `markSent` on the repository (`documents.md` §8) |
| 6 | PDF caching by document revision | ✅ | `PDFLibrary` actor: one file per document + template, keyed by the document's own content |
| 7 | iPad: preview in the builder's right pane, debounced, off the main thread | ✅ | `DocumentPreviewPane` (400 ms, `Task.detached`); pane from 700 pt, switchable Preview / Totals |
| 8 | iPad: drag the PDF out (`Transferable`), ⌘P | ✅ code · 🔲 device | `.draggable(url)` on the preview and ⌘P in the Document menu; a cross-app drag can't be driven from XCUITest, so try it by hand |
| 9 | Text-extraction tests per template | ✅ | `InvoicePDFTests` (9): four templates, 60-line pagination, Devanagari, draft watermark, Letter size, size and speed |
| 10 | Image snapshot tests per template | 🔲 deferred | see "Decisions", 3 |
| 11 | Friends-and-family TestFlight (5–10 UK and Indian businesses) | 🔲 | needs a TestFlight build (bundle ID and team, open since Phase 1) |
| 12 | Samples for the professional review | ✅ | `make pdf-samples` renders one PDF per `pdf` fixture (nine documents + a README describing each) |

**Spec first:** `spec/pdf/RENDERING.md` (new, normative: the view model, formatting, the template format, pagination,
fonts and caching), `spec/schema/pdf-layout.schema.json` + the four layouts, fixture kind `pdf` (9 cases: IN
intra/inter-state, composition, export, GB standard and reverse charge, a quote, a draft and a multi-page invoice),
`spec/documents.md` §8 "Sharing" (`sentAt`), and `spec/pdf/labels/en.json` grown to cover every drawn label.

## Definition of done

| Criterion | State |
|---|---|
| Every PDF fixture's text expectations pass | ✅ 9/9 `pdf` cases (view model) + text extracted back out of the rendered file in `InvoicePDFTests` |
| The 60-line invoice paginates correctly | ✅ repeated column headers, "Continued on next page", "Page n of m", every line once |
| Generation takes ≤ 1 s on an XR-class device | ✅ 60 lines in ~0.2 s on the simulator; the test asserts the cost stays within 12× a one-line invoice (machine-independent) plus a 3 s ceiling; 🔲 to confirm on a real device |
| CA and accountant confirm a GST invoice, Bill of Supply, export invoice and VAT invoice | 🔲 samples ready to send (see "Your next actions") |

## Test counts

| Command | Tests | Where |
|---|---|---|
| `make test-core-ios` | 85 (346 fixture cases) | macOS, `swift test` |
| `make test-data-ios` | 21 | macOS, `swift test` |
| `make test-pdf-ios` (new) | 10 | iOS 27 simulator |
| `make test-ui-ios` | 39 (8 of them the preview and its cache) | iOS 27 simulator |
| `make test-app-ios` | 11 UI tests (6 smoke flows, 5 screenshot tours) | iPhone 17 Pro and iPad Pro 13" |

## Found and decided during Phase 3

1. **The tax summary now sits beside the totals**, not above them (`RENDERING.md` §3.3). Stacked, an ordinary
   Indian invoice ran to two pages; side by side, classic fits 6 lines on one page instead of 5, minimal 5 instead
   of 3, modern 3 instead of 2 and compact 11 instead of 8.
2. **Payment, notes and signature are one closing region** (§3.4). They now move to the next page together, and if
   they miss the bottom by a little the QR shrinks (never below 56 pt ≈ 2 cm, still scannable) instead of opening a
   page that would hold nothing but a note and a signature line.
3. **Image snapshots are deferred, not forgotten.** Pixel comparisons of a Core Text render are tied to the OS's
   font rasterisation, so they fail on an Xcode update rather than on a real change. The content is covered by the
   `pdf` fixtures (strings) and by extracting the text back out of the rendered file (layout and pagination);
   templates are reviewed from the screenshot tour. Worth revisiting in Phase 6 with a tolerance-based comparison.
4. **A draft previews the *prepared* draft.** The preview and the live pane render `preparedDraft` — the same
   transform that decides what gets stored — so the seller and buyer blocks on the page are the ones that would be
   frozen at issue. Rendering `state.document` directly drew empty party blocks.
5. **The cache key is the document, not its timestamp.** Hashing the encoded document (plus template, accent and
   image ids) means an unsaved edit can never be served from a stale file, and the digest is FNV-1a rather than
   `hashValue`, which is seeded per process and would miss the cache on every launch.
6. **Devanagari** is drawn with the bundled Noto Sans Devanagari through a Core Text cascade list and embedded in
   the file. Extraction can reorder a pre-base vowel sign (वि), which is a PDF text-extraction limitation, not a
   rendering one (`RENDERING.md` §4).
7. **The iPad pane needs a wide *and* regular detail column.** With sidebar + list + detail, the detail column is
   ~570 pt on an 11-inch iPad in landscape and ~726 pt on a 13-inch, so the threshold is 700 pt: the live preview
   appears on a large iPad in landscape, in Stage Manager, or with the list collapsed. An iPhone in landscape is
   also wider than 700 pt but stays compact, where the form needs the whole screen, so the pane asks for a regular
   horizontal size class too.
8. **Sharing uses `UIActivityViewController`, not `ShareLink`.** Only its completion handler says whether the
   document was actually sent, and "Mark as sent?" must not appear over a share sheet the user cancelled.

## Code review (2026-09-21)

The `/code-reviewer` skill's scripts are empty scaffolding (`analyze()` returns no findings and the references are
placeholder text), so the change was reviewed by hand, as in Phase 2. Five things were found and fixed:

1. **The UPI QR was generated twice per render.** The renderer lays out once to count pages and once to draw; the
   QR box is a fixed size, so the counting pass now skips generating the image, and the `CIContext` is shared
   instead of built per code.
2. **Logo and signature drawing had no test at all** — the only drawn images besides the QR, and every business
   with a logo hits that code. `aLogoAndASignatureAreDrawnWithoutDisturbingTheLayout` renders with both.
3. **The PDF cache could grow without bound**: an issued document keeps a file per template for ever, and the
   system only empties the caches directory under disk pressure. It is now capped at 240 files, oldest first,
   with a test that fills it past the cap.
4. **`markSent` cited `documents.md` §9** (deleting a draft) instead of §8 (sharing).
5. **`documents.md` §8 said the prompt "appears once per document"**, which neither matches the code nor is what
   you want: declining leaves the document unchanged, so sharing again asks again. The spec now says that.

A sixth, cosmetic: the preview's local `print(_ url:)` shadowed Swift's `print`; it is now `airPrint(_:)`.

Two more came from CI, which builds with the runner's Xcode 16.4 rather than a local beta:

7. **The shared `CIContext` did not compile there** — the class is not marked `Sendable` in that SDK, so Swift 6
   rejected the `static let`. It is `nonisolated(unsafe)` now, with Core Image's thread-safety guarantee written
   down beside it. `ios/CLAUDE.md` now says plainly that CI is the stricter compiler.
8. **`make test-pdf-ios` was not in the workflow**, so nothing on CI compiled the renderer's own tests. It runs
   before the InvoiceUI step now — which is how 7 was found.
9. **The one-second render assertion measured the runner, not the code** (1.2 s there, 0.2 s locally). It now
   asserts that 60 lines stay within 12× a one-line invoice — that catches a layout pass turning quadratic on any
   machine — with a loose 3 s ceiling behind it.

## Your next actions

1. **Professional review:** run `make pdf-samples` (writes nine PDFs and a README to `build/pdf-samples`) and send
   them to the CA and the UK accountant with the new questions 15–18 in `docs/compliance/in-gst-invoice-rules.md`
   and 12–14 in `uk-vat-invoice-rules.md`, together with the fixture questions still open from Phase 2.
2. **TestFlight:** the friends-and-family round is the Phase 3 task that needs a build — bundle ID, team and an
   App Store Connect record are still open from Phase 1.
3. **On a device:** print to a real AirPrint printer, share to WhatsApp and Mail, drag the PDF from the preview into
   Files on an iPad, and check a 60-line invoice renders quickly on an older iPhone.
4. **Look at the templates** in the screenshot tour (`make test-app-ios`, attachments `27-*` and `28-*`) and say
   which of the four should be the default; it is `modern` today.
