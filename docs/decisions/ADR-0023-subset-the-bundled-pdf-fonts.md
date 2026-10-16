# ADR-0023: Subset the bundled PDF fonts

- **Status:** Accepted
- **Date:** 2026-10-17

## Context
`spec/pdf/RENDERING.md` §4 caps a one-page invoice at 300 KB "with the fonts subset", and ADR-0006 bundles the static
Noto Sans and Noto Sans Devanagari (about 2.6 MB of TTFs in each app). Core Graphics and Android 16's PDF backend
subset fonts as they embed them. Older Android does not: on Android 10 and 11 emulators every one-page sample was
968 KB, because Regular, SemiBold and Bold (621–631 KB each) were embedded whole (issue #32). India's phones are
largely on those versions, and invoices go out over WhatsApp on mobile data.

## Options considered
1. **Leave it** — PDFs of about 1 MB on older Android; breaks the §4 cap there.
2. **Subset at render time on Android** — no subsetter in the platform; a library (or our own) for one platform only.
3. **Bundle fonts that are already subset** — one script over `spec/pdf/fonts`, the same files on both platforms.
4. **Use the system fonts on old Android** — they are embedded whole too, and the PDF stops matching iOS.

## Decision
Option 3. `spec/tools/subset-pdf-fonts.sh` (fontTools) rewrites the files in place:

- **Noto Sans** keeps Basic Latin, Latin-1, Latin Extended-A, Romanian ș ț, Latin Extended Additional (Vietnamese),
  combining marks, general punctuation, currency signs (₹ £ € …), letterlike symbols, a few arrows and operators. It
  drops Greek, Cyrillic, IPA and the rest of Latin Extended-B/C/D.
- **Noto Sans Devanagari** keeps every glyph.
- Both drop TrueType hinting, which a PDF never uses. Layout features (kerning, ligatures, Devanagari shaping) and
  the `name` table (copyright, OFL) are kept. Noto declares no Reserved Font Name, so the names stay.

Glyph advances do not change, so line breaks and pagination are the same as before. Text in a script the fonts no
longer cover (a Greek or Cyrillic name) is drawn with the platform's own fonts, as Tamil or Bengali already were, and
stays extractable; both renderers test this.

## Consequences
- Noto Sans goes from about 625 KB to 115 KB a weight and Devanagari from about 246 KB to 167 KB: 1.77 MB less in each
  app (the Android release APK went from 4.36 to 3.49 MB).
- Measured with the review samples: a one-page invoice on Android 10 went from 968 KB to 205 KB (the Hindi sample from
  1,072 to 273 KB); on Android 16 from 67 to 43 KB; on iOS from 29 to 19 KB (GB) and 56 to 35 KB (IN), because the
  embedded subsets carry tables sized to the font they come from.
- Android unpacks the fonts into its cache directory; it now rewrites a copy that differs from the bundled font, so an
  app update brings the new fonts to existing installs.
- A Greek or Cyrillic name prints in the system font, which differs from the bundled one.
- The upstream fonts live in git history and at github.com/notofonts. To add a script, change the ranges in the
  script, run it on the upstream files, then `make sync-spec`.

## Revisit when
Customers regularly bill in a script the subset drops, or every supported Android version subsets fonts itself
(the minimum SDK reaches the first version that does).
