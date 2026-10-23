# Pick a look first, then build the first invoice one question at a time

## Context

ADR-0020 already made the first run friendlier (Welcome → 3-stage setup → checklist → a guided builder with 3
cards). The user reports it is still confusing for someone who doesn't know tax. The causes, from the code:

- **Tax questions come before anything visual.** Stage 1 asks "Registered (regular) / Composition scheme / Not
  registered", then the turnover tier ("Up to ₹5 crore"). Stage 2 asks for the GSTIN, PAN and state
  (`ios/.../Onboarding/OnboardingView.swift`, `android/.../onboarding/OnboardingScreen.kt`).
- **GST shows up even for people who don't charge it.** `spec/setup.md` §10 keeps the rate picker for non-charging
  registrations. The Add an item sheet always shows the rate chips, "My price already includes GST" and HSN/SAC.
- **No visual sense of what is being made.** The four PDF layouts (`spec/pdf/layout/{modern,classic,minimal,compact}.json`)
  and the six accent presets (`spec/design/tokens.json` → `pdf.accentPresets`) exist. But they are only offered as a
  plain-text picker in Settings, and as a preview switcher that never saves. A normal iPhone has no inline preview.

**What the user decided (2026-10-23):**

1. Template-first applies to the **first run**. New users pick a look, then fill in their first invoice step by step,
   and business details are asked along the way. This replaces the 3-stage setup. The look is remembered: later
   invoices skip the picker and go who → what → when → review.
2. **One question per screen**, with the chosen invoice shown live above the question.
3. **A clickable prototype comes first.** Native work starts only after the user has tried it with people who don't
   know tax.

This plan therefore delivers the prototype now and outlines the spec, iOS and Android work that follows sign-off.

## Phase A — clickable prototype (this change)

A phone-sized web prototype published as a private Artifact. It changes nothing in the repo.

### How to build it
- Call `Artifact` `quickstart` (intent `design`) first, as the tool requires. If it offers a Design type that can host
  a click-through, use it. Otherwise write one HTML page in the scratchpad after loading the `artifact-design` skill.
- Use vanilla HTML/CSS/JS with a small screen state machine and no build step.
- Use the visual language of `docs/design/design.md`: tokens v2 from `spec/design/tokens.json` (coral `#C2482A` on
  peach `#FFF5EF`), Bricolage Grotesque + Figtree from Google Fonts, and the §5 components (primary button, selectable
  card, chip, stepper, switch row, tip callout, "added for you" badge). Include the dark theme from §2.2.
- On desktop, show a 390×844 phone frame with a control strip beside it. On a phone, the prototype fills the screen
  and the controls sit behind a small "Prototype" pill.
- **Controls:** Country (India / UK), Start over, Jump to "second invoice", and a collapsible **How to test** script
  (below).
- **Money in the prototype:** integer minor units with simple GST/VAT maths. CGST + SGST 9 + 9 for a client in the
  same state, IGST otherwise. VAT 20% in the UK. Only the totals have to look right.

### Mini invoices (the thumbnails and the live preview)
- HTML/CSS versions of the four layouts that follow each JSON's block variants and its `accentUse`:
  - **modern:** a colour band across the top, zebra rows, an accent total row.
  - **classic:** logo on the right, ruled table, accent title and table header text.
  - **minimal:** no colour at all.
  - **compact:** logo on the left, tinted table header, tight rows.
- The same component draws the picker thumbnails, the live preview and the review page, all from one invoice state.
- Empty parts show soft placeholders ("Your business name"). The part being asked about is outlined, and the preview
  **zooms and pans to that part** so it can be read on a phone. Tapping the preview shows the whole page.
- The title follows the tax answer, as in `spec/tax/*.json`: "Invoice", "Tax Invoice" (GST-registered),
  "Bill of Supply" (composition), "VAT invoice".

### Screens, first run (India, with the UK differences noted)
1. **Welcome:** "Make your first invoice in about a minute." Buttons: "Let's start" and "I've used this app before".
2. **Pick a look:** four thumbnails filled with sample data in ₹/£ and six accent swatches (Minimal: "No colour").
   One line reads "Invoices in ₹ for India · Change"; the country is guessed from the phone, and Change opens India /
   UK. Button: "Use this look".
3. **What's your business called?** Hint: "The name your clients see at the top." Fills the From block.
4. **Where are you based?** India: address, city, PIN code, state. UK: address, town, postcode.
5. **Do you have a GSTIN?** (UK: "a VAT number?")
   - Two cards. **No:** "Most small businesses don't. We won't add GST." **Yes:** a field with a format hint. When the
     GSTIN is valid, it shows "Karnataka · PAN filled in".
   - Below that, "GST scheme: Regular (most businesses) · Change" reveals Composition, in plain words.
   - "Not sure?" opens a sheet: "If you'd registered, you'd have a 15-character number on your GST certificate.
     Choose No; you can add it later in Settings."
   - The invoice title and the GSTIN line change live.
   - **No turnover question.** It defaults to the first tier and moves to Settings.
6. **Who is this invoice for?** Name, plus an optional "Add their address". Only if the seller has a GSTIN: "Their
   GSTIN (optional): add it if they're a business that claims GST back."
7. **What are you charging for?**
   - What did you sell? / How many? (stepper) / Price for one.
   - **Only when the seller charges tax:** "How much GST?" chips 0/5/18/40 with "Not sure? Most services are 18%",
     plus "My price already includes GST".
   - A live line total, then "+ Add another".
8. **When should they pay?** Right away / 7 / 15 / 30 days → "Due Fri, 7 Nov".
9. **How should they pay you?** Optional, with Skip. India: UPI ID (a QR appears on the invoice) or bank. UK: account
   name, sort code, account number.
10. **Review & send**
    - The full invoice, plus **Change look** (back to the picker, now showing the user's own data).
    - Tapping any section jumps back to its step.
    - The lock tip from design.md §6.6, a "More options" stub (discount, notes, dates), and send tiles: WhatsApp /
      Email / Print / Save PDF.
11. **Sent:** the "What happens next" timeline, then "Make another invoice" or "Go to Home".
12. **Second invoice:** 3 steps plus review. Who (with recent-client chips) → What (with saved-item chips) → When →
    Review. This shows how fast repeat invoices are.

Progress reads "Step n of 7" with the stepped bar. Back is on every step, and answers are kept.

### How to test (shown in the control strip, for the user's testers)
Ask someone who doesn't know GST/VAT to "send Ravi an invoice for 2 logo designs at ₹2,500, due in a week" without
help. Note where they hesitate, what they ask, and how long it takes. Run it once as a GSTIN holder and once without.

### Optional (decide while building)
A "Something confusing?" button on each screen that saves a note tagged with the screen name. This only works if the
runtime offers a shared store (`artifact-capabilities` skill); otherwise leave it out.

### Verification
- Open the page in Chrome (claude-in-chrome) at 390×844 and at desktop width.
- Click through India with GSTIN, India without GSTIN, UK with a VAT number and UK without. Then run the second-invoice
  path and Change look from Review.
- Check that the console has no errors, that the dark theme works, that there is no horizontal scroll at 390 px, and
  that totals are right for the sample (2 × ₹2,500 at 18%, same state → CGST ₹450 + SGST ₹450 = ₹5,900).
- Publish, give the user the link, and wait for their feedback before Phase B.

## Phase B onward — after the user signs off the prototype (outline; re-planned in detail then)

Work in a new worktree off `origin/main`, not the user's checkout. Local `main` is behind origin, and Xcode is open
there. Track the work in a GitHub issue on alfinb27/InvoiceBuilder, per the repo practice. The order is spec → iOS →
Android, as the golden rules require.

**B. Spec and decisions**
- **`docs/decisions/ADR-0024-…`:** "Pick a look first; the first invoice is the setup". It amends ADR-0020's first
  run. 0023 is taken by open PR #40.
- **`spec/setup.md`**
  - §3: Welcome → look → steps.
  - The registration is derived from the answer: India, no GSTIN → `unregistered`; GSTIN → `regular` unless the user
    chose composition. UK: VAT number → `vatRegistered`. GENERIC: "Do you charge tax on your sales?"
  - The turnover tier defaults to the first tier.
  - The business, its numbering series and the draft are created when the "about you" steps finish (today nothing is
    written until Finish).
  - §3.2: the checklist is replaced or removed.
  - §10: the rate picker, "includes tax" and the product code are hidden when the registration doesn't charge tax.
- **Fixtures:** a small fixture set for the registration derivation, if it becomes a core function, with
  `"reviewed": false`.
- **`spec/documents.md`:** new invoices use the step flow, and an existing draft opens on Review with tap-to-edit.
  Whether the 3-card guided builder survives is decided from prototype feedback.
- **Other docs:** `docs/design/design.md` gets the new §6 screens and §7 words. Add a row to `docs/parity.md`. Copy
  the final prototype into `docs/design/`.
- Raise the derived-registration and composition wording with the CA review (#18).

**C. iOS** (`ios/Packages/InvoiceUI/Sources/InvoiceUI/…`)
- **Rework:** `Onboarding/OnboardingView.swift`, `OnboardingViewModel.swift`, `WelcomeView.swift`, and the stages in
  `InvoiceCore/Setup/BusinessRules.swift`.
- **New `TemplatePickerView`:** it renders real page-1 thumbnails of a sample document through `PDFLibrary` /
  `PDFRenderer` with `PDFTemplateStore`. Reuse it in Settings → `DefaultsPage` (`Settings/SettingsSection.swift:173`)
  in place of the text picker.
- **Step flow:** wraps the existing `DocumentViewModel` (autosave, `DocumentRules`, issue path unchanged). The live
  preview reuses `DocumentPreviewPane` (`Documents/DocumentPreviewView.swift:283`), now on iPhone too.
- **`Documents/AddItemSheet.swift`:** hide the rate section when the registration doesn't charge tax.
- **Fix:** the preview's template switch saves the choice to the document (`DocumentPreviewView.swift:73`).

**D. Android** (`android/app/src/main/kotlin/app/invoicebuilder/android/…`)
- The same names and changes as on iOS: `onboarding/OnboardingScreen.kt`, `OnboardingViewModel.kt`,
  `WelcomeScreen.kt`, `documents/DocumentPreview.kt` (`DocumentPreviewPane`, `TemplateSwitcher`),
  `documents/AddItemSheet.kt` (`RateSection`), and `settings/SettingsSection.kt` (template picker).
- Verify with `make validate-spec`, `make check-ios`, the Android unit/lint/device tests, and the iOS accessibility
  audit plus Android ATF checks on the new screens.
