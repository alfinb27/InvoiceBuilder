#!/bin/sh
# Subsets the bundled PDF fonts in spec/pdf/fonts, in place (ADR-0023, spec/pdf/RENDERING.md §4).
#
# Noto Sans keeps Latin (Basic Latin, Latin-1, Latin Extended-A, Romanian ș ț, Latin Extended Additional for
# Vietnamese), combining marks, punctuation, currency signs (₹ £ € …), letterlike symbols and a few arrows and
# operators. Noto Sans Devanagari keeps every glyph. Both lose their TrueType hinting, which a PDF never uses. Text in
# other scripts falls back to the platform's own fonts, as Tamil or Bengali already do.
#
# Running it again on subset files changes nothing. It needs fontTools (`pip install fonttools`); run
# `make sync-spec` afterwards to copy the fonts into both apps.
set -eu

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
FONTS="$ROOT/spec/pdf/fonts"
LATIN="U+0000-017F,U+0218-021B,U+02C6-02DD,U+0300-036F,U+1E00-1EFF,U+2000-206F,U+20A0-20CF,U+2100-214F,U+2190-2199,U+2212,U+2215,U+25CF,U+FB00-FB06,U+FEFF,U+FFFD"

subset() { # font, unicodes
  pyftsubset "$1" --unicodes="$2" --layout-features='*' --no-hinting --name-IDs='*' --name-languages='*' \
    --notdef-outline --output-file="$1.subset"
  mv "$1.subset" "$1"
}

for font in "$FONTS"/NotoSans-*.ttf; do subset "$font" "$LATIN"; done
for font in "$FONTS"/NotoSansDevanagari-*.ttf; do subset "$font" '*'; done
ls -l "$FONTS"/*.ttf
