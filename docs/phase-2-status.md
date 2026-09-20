# Phase 2 status (2a: tax engine and document core · 2b: document builder)

- **As of:** 2026-09-20
- **Summary:** the tax engine and the document core are complete and proven by fixtures (337 of 337 on iOS), and
  the iPhone/iPad builder creates, autosaves, issues, duplicates and converts invoices and quotes end to end on
  simulators. Still to do: the professional review of the fixtures (a Phase 2a gate), a hallway test and a few
  on-device checks.

## Phase 2a: tax engine and document core (plan § Phase 2a)

| # | Task | Status | Evidence |
|---|---|---|---|
| 1 | `round` and `allocate` (largest remainder) | ✅ | `Tax/SpecMath.swift`; `rounding` 39 and `distribute` 7 fixtures |
| 2 | Rule matching and components | ✅ | `Tax/TaxEngine.swift` Steps 0–5 |
| 3 | Inclusive-price back-calculation | ✅ | line and invoice level; e.g. `in-inter-inclusive-shipping`, `gb-inclusive-standard-and-reduced` |
| 4 | Discount allocation and shipping rules | ✅ | principal supply (IN) and apportion by rate group (GB, generic) |
| 5 | Reverse charge, exports (LUT / IGST), composition, unregistered, GB outside scope and invoice-level rounding, generic compound tax | ✅ | `spec/fixtures/tax/*.json` |
| 6 | Home-currency conversion | ✅ | `home` totals; VAT in sterling per rate (`homeTax`) |
| 7 | Required-field warnings | ✅ | config `checks` → `issues`, in config order |
| 8 | Number allocator (tokens, fiscal-year reset, IN 16-character limit) | ✅ | `Numbering/NumberAllocator.swift`; `numbering` 13 fixtures |
| 9 | `status()` and `AmountInWords` | ✅ | `status` 16 and `words` 14 fixtures; UPI links 3 |
| 10 | `IssueDocument` and `ConvertQuote` in one `InvoiceData` transaction | ✅ | `GRDBDocumentService` (issue, duplicate, convert, delete draft); `DocumentTests` |
| 11 | Fixtures grown to at least 80, then sent for review | ✅ 105 tax + 26 document · 🔲 review | 57 new tax cases (IN, GB, generic combinations and 13 error cases) |

**Spec first:** `spec/documents.md` (new, normative: draft defaults, the edits that move other fields, lines and
catalogue prices, snapshots, autosave, `IssueDocument`, duplicate, convert, delete); `ENGINE.md` final for v0
(errors with the line they concern, `invalid_input` for negative discounts and shipping); fixture kind `document`
(`defaults`, `linePrice`); `supplyTypeDefaults` in the tax-config schema and `IN.json` / `GB.json`; migration
`0002_document_sequence` (`document.sequence`, so Settings can refuse a next number at or below an issued one).

### Definition of done (2a)

| Criterion | State |
|---|---|
| 100% of fixtures pass | ✅ 337/337: tax 105, document 26, rounding 39, distribute 7, words 14, status 16, UPI 3, numbering 13, format 25, input 29, field 41, validation 19 |
| Branch coverage ≥ 90% on `TaxEngine` | ✅ 93.7% of regions, 98.2% of lines (`swift test --enable-code-coverage`; Swift reports regions, its branch proxy) |
| Reviewer comments resolved or recorded as ADRs | 🔲 waiting for the CA and the UK accountant (questions 11–14 and 9–11 added to `docs/compliance/`) |
| Config v1 tagged | 🔲 after the review |

## Phase 2b: document builder (plan § Phase 2b)

| # | Task | Status | Evidence |
|---|---|---|---|
| 1 | Builder: client picker + quick add, type toggle, dates with payment-terms presets | ✅ | `Documents/DocumentBuilderView.swift`, `PickerSheets.swift` |
| 2 | Supply type, place of supply, reverse charge, inclusive prices, currency and exchange rate (under "Tax and currency") | ✅ | shown only when the config and registration use them |
| 3 | Lines from the catalogue (search, multi-add) or one-off; swipe delete, reorder, duplicate | ✅ | `LineEditorView.swift`; `LineItemRules` in core |
| 4 | Invoice discount, shipping, live totals with the tax breakdown, notes and terms | ✅ | `TotalsView` renders the engine result only |
| 5 | Warnings banner from the engine's issues | ✅ | blocking problems in red, compliance warnings in amber |
| 6 | Autosave (500 ms debounce, on leaving and going to the background) | ✅ | `DocumentViewModel` (chained saves; an untouched draft is deleted on close) |
| 7 | Issue (confirm with the number), duplicate, convert quote → invoice | ✅ | `IssuedDocumentView` for issued documents |
| 8 | Keyboard toolbar, decimal pads per locale, Dynamic Type | ✅ | Done button above the keyboard; a comma-decimal pad types `.` (`DecimalPadText`); at accessibility text sizes labels and amounts stack (`AdaptiveRow`, large-text screenshot tour) |
| 9 | iPad: two-pane builder (form + totals and tax panel) | ✅ | two panes from 760 pt; the PDF preview replaces the panel in Phase 3 |
| 10 | iPad: shortcuts and popover line editor | ✅ | ⌘N / ⇧⌘N (menu bar), ⌘↩ issue, ⌘D duplicate line, ⌥⌘L add line; the line editor is a popover in regular width |
| 11 | View-model tests, UI smoke tests, screenshots | ✅ | `DocumentViewModelTests` (9) + decimal pads (1), `DocumentSmokeTests` (2), builder and large-text screenshot tours on iPhone 17 Pro and iPad Pro 13" |

### Definition of done (2b)

| Criterion | State |
|---|---|
| A 5-line GST invoice issued in under 60 s by a new user | 🔲 hallway test to do (the smoke test does client + item + one-off line + issue in ~35 s of scripted taps) |
| View-model tests for the builder intents | ✅ |
| No totals differing from the engine output | ✅ every total on screen and stored comes from `TaxEngine.compute` |
| Drafts survive the app being killed | ✅ desk (autosave on change, leave and background) · 🔲 kill test on a device |

## Test counts

| Command | Tests | Where |
|---|---|---|
| `make test-core-ios` | 84 (337 fixture cases) | macOS, `swift test` |
| `make test-data-ios` | 21 | macOS, `swift test` |
| `make test-ui-ios` | 31 (view models, routers, image processing, decimal pads) | iOS 27 simulator |
| `make test-app-ios` | 9 UI tests (5 smoke flows, 4 screenshot tours) | iOS 27 simulator, iPhone 17 Pro and iPad Pro 13" |

## Found and decided during Phase 2

1. **Round-off in foreign currencies:** the engine rounds any currency to a whole unit when the config's grand-total
   rounding is on, so a USD export invoice would lose cents. New foreign-currency drafts start with round-off off
   (`documents.md` §2); the CA is asked to confirm (question 11).
2. **Supply-type defaults are config data** (`supplyTypeDefaults`), not code: IN foreign clients default to export
   under LUT when the business has a LUT reference, else export with IGST; GB overseas businesses to "services to an
   overseas business".
3. **Catalogue prices** convert to the document's currency and price basis with one rounding (`documents.md` §3.1);
   without an exchange rate the line is added at 0 and the editor asks for the price.
4. **Snapshots** are flat JSON objects: the engine's seller/buyer fields plus what the PDF prints. Drafts re-take
   them on every save; issuing freezes them. A deleted client's last snapshot stays on its drafts.
5. **Images used by issued documents** are never tombstoned when the logo or signature changes (`setup.md` §9).
6. **Not in Phase 2** (plan Phase 4): void, payments, accepted/declined quotes, and revising an issued document.
   Issued documents are read-only for now.
7. **Toolchain:** `xcode-select` was back on the Command Line Tools during this phase; the tests above ran with
   `DEVELOPER_DIR` set to Xcode (`swift test`) and Xcode-beta (simulators).

## Code review (2026-09-20)

The multi-agent `/code-review` could not run (the session hit its rate limit), so the change was reviewed by hand.
Four defects were found and fixed, each with a test:

1. **A deleted draft could never be saved again** (`GRDBDocumentRepository.saveDraft` threw `not_a_draft`/not found
   for a tombstoned row). The builder deletes an emptied draft when it closes but keeps the same id, so editing it
   again lost every later change with only a small "couldn't save" note. Saving now revives the draft
   (`documents.md` §8); `DocumentTests.aDeletedDraftComesBackWhenItIsEditedAgain`.
2. **A typed amount survived a currency change in the wrong unit**: "12.50" shipping kept 1250 minor units when the
   document moved to yen (¥1,250 instead of nothing). Values whose text no longer fits the new currency are cleared;
   `DocumentViewModelTests.amountsThatDoNotFitTheNewCurrencyAreCleared`.
3. **Issue and duplicate could work from a stale stored draft** when the last autosave failed. Both now stop and
   report instead of issuing or copying an older version (`saveBeforeAction`).
4. **The line editor opened behind the catalogue sheet** when an item's price needed the exchange rate; the picker
   now closes first.

## Your next actions

1. **Professional review (Phase 2a gate):** send `spec/fixtures/tax/` (105 cases with `explain` strings) and
   `spec/fixtures/documents/` to the CA and the UK accountant with the open questions in `docs/compliance/`. Their
   answers flip cases to `"reviewed": true` or become fixes/ADRs; then tag config v1.
2. **Hallway test:** a new user issues a 5-line GST invoice (target under 60 s) on an iPhone.
3. **On a device:** kill the app mid-edit and reopen (the draft must be there), try the iPad shortcuts with a hardware
   keyboard, and resize the iPad window with the builder open.
4. **Toolchain:** `sudo xcode-select -s /Applications/Xcode.app` so `make test-core-ios` / `make test-data-ios` use
   Xcode rather than the Command Line Tools.
5. **Still open from earlier phases:** TestFlight build (bundle ID, team), accounts, the two-device sync run.

**Next:** Phase 3, PDF generation, templates, UPI QR and sharing.
