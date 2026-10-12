# ADR-0020: A friendlier first run and a new visual design

- **Status:** Accepted
- **Date:** 2026-10-10
- **Amends:** `spec/design/tokens.json` (v2), `spec/setup.md` §3, `spec/documents.md` §3, §6, §8; the low-fi path in
  `docs/design/wireframes.html`

## Context
The v1 screens put everything in front of a first-time user at once: onboarding is five form steps, the builder is one
long form with supply type, place of supply, reverse charge, currency, discount and notes next to the client and the
lines, and Issue is a toolbar button with a confirmation alert. People who have never written a GST or VAT invoice
don't know what most of those fields mean, and nothing tells them what Issue will do. The look (blue on grey, system
fonts) is also close to admin software. `docs/design/design.md` (mockups: the "InvoiceBuilder — Friendly first run"
design canvas) proposes a guided first run and a warmer theme.

## Options considered
1. **Restyle only** (new colours and fonts on the existing screens). Cheap, but the overload stays.
2. **A separate "simple mode"** beside the full builder. Two builders to keep in step on two platforms, and users
   would need to know which one they want.
3. **One guided builder with the advanced fields folded away**, a three-stage setup over the same five steps, and a
   Review & send screen in place of the Issue alert. Same data, same rules, fewer things on screen at once.

## Decision
Option 3, as written in `docs/design/design.md`:
- **Theme:** `tokens.json` v2: coral brand on a peach ground (light), the proposed dark palette, new tokens
  (`brandPressed`, `brandTint`, `surfaceSubtle`, `borderStrong`, `control`, `tip`, `tipOn`, `tipIcon`, `highlight`,
  `scrim`), larger radii, and the type roles with their font families. Three light status colours are darkened so
  every chip passes 4.5:1 on its tint.
- **Fonts:** Bricolage Grotesque (display: 600, 700) and Figtree (text: 400–700), static instances cut from the OFL
  Google Fonts sources, bundled in both apps with their licences (~340 KB). All sizes go through Dynamic Type /
  `sp`. PDFs keep Noto Sans (ADR-0006).
- **Setup** (`setup.md` §3): a Welcome screen, then the five steps grouped into three stages (Where you work · Your
  business · Getting paid, the last one skippable). Nothing is written before Finish, as before.
- **First-run home:** a four-item checklist and empty ₹0 tiles until the first invoice is issued, then the dashboard.
- **Guided builder** (`documents.md` §3): three numbered cards (who, what, when), everything else under "More
  options", a pinned totals bar. Lines are added and edited in one "Add an item" sheet (saved items or something new,
  rate chips, "price includes tax" per line, "save to my items").
- **Review & send** (`documents.md` §6, §8): issuing happens from a review screen that shows the number the document
  will get, says it will be locked, and sends it in the same step (WhatsApp, email, print or save as PDF).
- **Words:** the screens say "Send" for issuing, "Waiting to be paid" for outstanding, "My saved items" for the
  catalogue (`design.md` §7). Code, spec and database names do not change (`IssueDocument` stays).

## Consequences
- Each app grows by the font files. Text in the system font (navigation bars, alerts, share sheets) stays the system
  font.
- Every screen moves to the new tokens; screens the mockups don't cover (client form, settings, lists, issued
  documents) follow the same components.
- UI tests and screenshots change with the flows; the accessibility audits keep running on the new screens.
- The dark theme, iPad/tablet layouts of setup and home, and the UK variants were not mocked up; they follow the
  tokens and are reviewed on device before release.

## Revisit when
Usability sessions show that people still stall in setup or the builder, or a user's PDF accent colour should also
theme the app (`design.md` §9).
