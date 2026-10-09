# InvoiceBuilder — first-run design (v1)

The visual theme and first-run flow for both apps. It replaces the look in `spec/design/tokens.json` v1 (blue
brand on grey) and gives the low-fi `wireframes.html` a friendlier first-time path. The source mockups are the
Design canvas **"InvoiceBuilder — Friendly first run"** (six 390×844 iPhone artboards, click-through).

**Status:** accepted (ADR-0020). The light theme matches the mockups. The dark theme in §2.2 passes the contrast
checks in `make validate-spec` but has not been mocked up or reviewed yet. `spec/design/tokens.json` v2 holds the
values; where this page and the tokens differ, the tokens win (three light status colours were darkened to pass
4.5:1, and the dark values the table leaves out were added).

## 1. Principles

1. **One question at a time.** Each screen asks for one thing, in everyday words, and says why it asks.
2. **Explain the tax, don't ask about it.** The app works out GST/VAT from the country, registration and client. The
   user only sees the result, labelled "added for you".
3. **Show what's coming.** Empty states preview what will appear (₹0 tiles, the checklist) instead of being blank.
4. **Hide the advanced options.** Supply type, place of supply, reverse charge, currency, discount and notes go
   under "More options". Most invoices never need them.
5. **No surprises at Issue.** Before sending, the user is told that sending assigns the number and locks the invoice.
6. **Warm, not corporate.** A peach ground, a coral brand colour and a rounded display face, kept clearly apart
   from the Mechanix Pro admin look.

## 2. Colour

### 2.1 Light (as in the mockups)

| Token (`tokens.json` key) | Hex | Use |
|---|---|---|
| `brand` | `#C2482A` | Primary buttons, selected chips/cards, progress, active tab, links |
| `brandPressed` *(new)* | `#9E3820` | Pressed/hover brand, text on `brandTint` |
| `brandOn` | `#FFFFFF` | Text/icons on `brand` (4.9:1) |
| `brandTint` *(new)* | `#FDE3D8` | Selected chip fill, avatar fill, hero panel, "added for you" badge |
| `background` | `#FFF5EF` | Screen ground |
| `surface` | `#FFFFFF` | Cards, sheets, tab bar, totals bar |
| `surfaceMuted` | `#F8ECE5` | Segmented-control track, stepper buttons, row dividers |
| `surfaceSubtle` *(new)* | `#FBE9E0` | "More options" row |
| `border` | `#EEDFD6` | Card borders, bar borders |
| `borderStrong` *(new)* | `#E2CFC4` | Inputs, unselected chips, dashed empty tiles |
| `control` *(new)* | `#CDB3A6` | Unchecked radio/checkbox ring, switch track (off) |
| `textPrimary` | `#2A2135` | Body and headings (15.4:1 on white) |
| `textSecondary` | `#6B5F72` | Hints, captions, inactive tabs (5.6:1 on `background`) |
| `textTertiary` | `#9A8C92` | Chevrons and decorative icons only, never text |
| `tip` *(new)* | `#E3F0FF` | Tip/notice callouts, line-total preview |
| `tipOn` *(new)* | `#1D3A5F` | Text on `tip` (10:1) |
| `tipIcon` *(new)* | `#2C5C94` | Icons on `tip` |
| `highlight` *(new)* | `#8EC5FF` | Illustration accent ("PAID" stamp) |
| `scrim` *(new)* | `#5A4A55` | Backdrop behind sheets (use at ~70% opacity in-app) |

Shadows use the ink colour `rgba(42,33,53,α)`: cards α 0.08–0.12, totals bar α 0.06.

`success`, `warning`, `danger`, `info` and the `status` chip colours stay as in `tokens.json` for now. Check them
against `#FFF5EF` before release.

### 2.2 Dark (proposed, not yet mocked up)

| Token | Hex | Check |
|---|---|---|
| `brand` | `#F0866A` | 7.1:1 on `background` |
| `brandOn` | `#2A1410` | 6.9:1 on `brand` |
| `brandTint` | `#4A2A24` | — |
| `background` | `#1A1520` | — |
| `surface` | `#241D2B` | — |
| `surfaceMuted` | `#2F2637` | — |
| `border` | `#3D3346` | — |
| `textPrimary` | `#F7EFEA` | 15.8:1 on `background` |
| `textSecondary` | `#CDBFC6` | 9.2:1 on `surface` |
| `textTertiary` | `#B3A4AC` | 6.9:1 on `surface` |
| `tip` / `tipOn` | `#1C2B3D` / `#CFE3FF` | 11:1 |

### 2.3 Brand alternatives
The mockups have a colour tweak with `#C2482A` (coral, default), `#1F5FAD` (blue), `#7A3E9D` (purple) and `#2A2135`
(plum-ink). These are options for the app theme, separate from the PDF `accentPresets`.

## 3. Typography

| Role | Font | Size / weight | Maps to |
|---|---|---|---|
| Hero title | Bricolage Grotesque | 31 / 700, tracking −0.6, line height 1.12 | `largeTitle` |
| Screen title | Bricolage Grotesque | 26–27 / 700, tracking −0.4 | `title` |
| Sheet / card title | Bricolage Grotesque | 19–22 / 700 | `title` (smaller) |
| Amount, large | Bricolage Grotesque | 26 / 700, tabular digits | `amountLarge` |
| Section heading | Figtree | 16 / 700 | `headline` |
| Body / row title | Figtree | 15–16 / 600 | `body` |
| Button | Figtree | 17 / 700 | `headline` |
| Hint / secondary | Figtree | 13 / 400 | `footnote` |
| Caption, tab label | Figtree | 11–12 / 600 | `caption` |
| Overline | Figtree | 13 / 700, uppercase, tracking 0.6 | — |

- Both fonts are free under the OFL (Google Fonts). Bundle the static weights used: Bricolage 600/700 and Figtree
  400/500/600/700.
- Map every size to Dynamic Type / `sp` text styles so they scale. Never fix line heights in a way that clips.
- Devanagari and other scripts fall back to Noto Sans Devanagari, as the PDF does. PDFs keep Noto Sans (ADR-0006).

## 4. Shape and spacing

- Spacing uses the existing `space` scale. Screen gutters are 20–24, card padding 14–18, and gaps between cards 12.
- **Radii** (new values for `radius`): input/stepper 14, chip 22 (pill), card 20–22, primary button 16, sheet top 26,
  hero panel 24, avatar circle.
- **Heights:** primary button 54–56, input 50, chip/stepper button 44, list row 52–60, tab bar items 48. The minimum
  touch target stays 44.

## 5. Components

| Component | Spec |
|---|---|
| Primary button | Full width, `brand` fill, `brandOn` 17/700 text, radius 16, height 56; optional trailing arrow |
| Text button | `brand` 15/600, height ≥ 44, no fill (e.g. "I've used this app before", "Keep as draft") |
| Selectable card (radio) | `surface`, 1 px `border`; selected: 2 px `brand` border + filled radio dot. 40 pt rounded icon tile in `brandTint` |
| Chip (single choice) | Pill, 44 high, 14/600; off: `surface` + 1 px `borderStrong`; on: `brandTint` + 2 px `brand` |
| Numbered section card | `surface`, radius 20, a 24 pt `brand` circle with the step number + 16/700 question as title |
| Checklist row | 26 pt ring (`control`) or filled `brand` check; title 15/600 + hint 13; chevron `textTertiary`; done rows struck through in `textSecondary` |
| Progress (stepped) | 3 equal 5 pt bars, 6 gap, with stage labels underneath; current stage `brand` + bold label |
| Progress (bar) | 6 pt track `#F1E2D9`, `brand` fill, "n of 4" label |
| Tip callout | `tip` fill, radius 12–16, info or lock icon in `tipIcon`, 13 pt `tipOn` text |
| Badge | 12/600 pill, `brandTint` fill, `brandPressed` text (e.g. "added for you") |
| Totals bar | Pinned `surface` bar with a top border and shadow: subtotal and tax rows (14, secondary), Total 16/700 + amount 26/700, primary button |
| Bottom sheet | `surface`, top radius 26, 40×5 grabber, title + Cancel, over `scrim` |
| Segmented control | `surfaceMuted` track, radius 14; selected segment `surface` with a small shadow |
| Stepper | Input-shaped box with − / value / + ; buttons 44, `surfaceMuted` |
| Switch row | `background` fill row: title + hint that changes with the state; track `brand` on / `control` off |
| Empty stat tile | 1.5 pt dashed `borderStrong`, "₹0" in display font + 12 pt label |
| Tab bar | 5 items, always with labels (Home, Invoices, Clients, Items, Settings); active `brand`, inactive `textSecondary` |

Icons are 2 pt stroke line icons (SF Symbols on iOS, Material Symbols Outlined on Android). Don't use emoji.

## 6. Screens and flow

```
Welcome → Setup (3 stages) → First-run home ─┬→ Guided invoice ⇄ Add an item
                                             └→ Review & send → Home (status "Sent")
```

### 6.1 Welcome
Logo + name, an illustrated hero (invoice card + "PAID" stamp), the title "Send a proper invoice in about a minute.",
three numbered promises (set up once ~2 min · add client and items, tax worked out · send on WhatsApp/email and see
who paid), a privacy line ("Your data stays on your phone. No account needed."), the primary button "Let's get
started" and the text button "I've used this app before" (iCloud restore, ADR-0015).

### 6.2 Setup — three stages instead of five steps
The five onboarding steps in `spec/setup.md` §3 are unchanged in the data. They are grouped under three labelled
stages:

| Stage | Covers setup.md steps | Notes |
|---|---|---|
| Where you work | 1 Country, 2 Registration | Country as cards (India · GST ₹ / United Kingdom · VAT £ / Somewhere else). The registration question appears below once a country is picked, as chips. Tip: "Not sure? Pick 'Not registered'. You can change it later in Settings." |
| Your business | 3 Business | Name and address first; tax IDs shown only when the registration needs them (§3 rules) |
| Getting paid | 4 Bank & UPI, 5 Logo & signature | Marked optional, with a visible "Skip for now" |

Each stage has a one-line reason under its title (e.g. "This decides which tax goes on your invoices…").
"Step n of 3" plus the stepped progress bar sit at the top. Nothing is written before Finish, as now.

> The Settings tip assumes the registration stays editable after onboarding (`setup.md` §4 says it does; country
> and currency do not).

### 6.3 First-run home
The greeting with the business name, then the **"Get ready to send your first invoice"** checklist (Set up your
business ✓ · Add your first client · Save something you sell · Send your first invoice "15 invoices free, no
sign-up") with "1 of 4" progress. Below it is the primary button "Create an invoice", with the note that the client and items can be
added along the way. Under the overline "Once you start sending" are three ₹0 tiles: Waiting to be paid / Past
due date / Paid this month (= outstanding / overdue / paid this month). The checklist goes away for good once the
first invoice is issued. After that the normal dashboard (wireframe 2) takes over.

### 6.4 Guided invoice (builder)
The header has Close, "New invoice" with a "Draft saved" sub-label (autosave, `documents.md` §5), and Preview. Below
the line "Three quick parts. We handle the tax maths." come three numbered cards:

1. **Who is it for?** The client with an avatar and a summary line (city, state, "GSTIN added"), plus Change.
2. **What are you charging for?** Line rows (name; "qty × price · GST n%"; amount) and a dashed "Add an item" button.
3. **When should they pay?** Chips for Right away / 7 / 15 / 30 days (default = `paymentTermsDays`) that update "Due …".

Then the collapsed **More options** row ("Discount, notes, currency. Most invoices don't need these.") and the
pinned totals bar: Subtotal, "GST 18%" + the "added for you" badge, Total, and "Review & send". On iPad the live PDF
preview stays beside the form (wireframe 4).

### 6.5 Add an item (sheet)
Tabs: My saved items / Something new. Fields: **What did you sell?** (hint: "This is what your client sees") ·
**How many?** stepper · **Price for one** · **GST rate** chips 0 / 5 / 18 / 40 % + "Other rates" (the full list of
config rates in force) with the hint "Most services are 18%…" · switch **My price already includes GST** with a hint
that changes with the state · a live line-total callout ("2 × ₹2,500 + ₹900 GST = ₹5,900") · the checkbox **Save to
my items so I can reuse it** (on by default) · "Add to invoice". The labels for HSN/SAC, unit and discount appear
only when needed (B2B, goods, More options).

### 6.6 Review & send
A mini preview with the client, total, item count and due date, plus "See full invoice". A lock tip: "Sending gives
it the number INV/26-27/0001 and locks it, so your GST records stay correct. Not ready? It stays a draft you can
edit." Under **Send it by** are four tiles (WhatsApp, Email, Print, Save PDF), and the primary button label follows the
choice ("Send on WhatsApp", "Send by email", "Print invoice", "Save as PDF"). **What happens next** is a short
timeline: shown as Sent → a reminder on your phone if unpaid by the due date (nothing is sent to the client) →
"Mark as paid". Secondary action: "Keep as draft". The number shown is the preview of the next number in the
series, and it is allocated only on Issue (`documents.md` §6).

## 7. Words

| Instead of | Say |
|---|---|
| Client / Customer selector | Who is it for? |
| Line items | What are you charging for? |
| Payment terms / Due date | When should they pay? |
| Description | What did you sell? |
| Quantity | How many? |
| Unit price / Rate | Price for one |
| Tax inclusive | My price already includes GST/VAT |
| Issue | Send (explained in the lock tip) |
| Outstanding / Overdue | Waiting to be paid / Past due date |
| Catalogue | My saved items |
| Advanced | More options |

Use "GST" for IN, "VAT" for GB and the configured tax name for GENERIC. Use the tone of a helpful person: short sentences, no
exclamation marks, no jargon without a hint.

## 8. Accessibility

- Text meets 4.5:1 (all pairs above were checked). `textTertiary` is for decoration only.
- Selection is shown by border weight and fill as well as colour.
- Use real controls with accessibility traits/roles: radio group for country, toggle buttons for chips, a switch,
  a stepper with "Fewer"/"More" labels, and labelled icon-only buttons (Close, Back).
- Touch targets are ≥ 44 pt and layouts scale with Dynamic Type.

## 9. Open items

- Mock up and review the dark theme (§2.2), plus iPad/tablet layouts for setup and home.
- Re-check the `status` chip colours on the new ground.
- Design screens not covered yet: Your business / Getting paid stages, client form, saved-items tab, full preview,
  the "Other rates" picker, and the UK (£/VAT) variants.
- Decide whether the app theme colour should follow the user's PDF accent.
- ~~Update `spec/design/tokens.json` (and its schema) with the new keys marked *(new)* once this is approved.~~ Done
  in tokens v2.
