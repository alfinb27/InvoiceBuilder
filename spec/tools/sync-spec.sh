#!/usr/bin/env bash
# Copies the runtime spec files into each app core module's bundled resources.
#   sync-spec.sh           copy into every module that exists
#   sync-spec.sh --check   fail if any existing module's bundled copy is missing or out of date
# A module that does not exist yet is skipped; once its root folder exists, its bundled copy is required.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
MODE="${1:-sync}"
case "$MODE" in
  sync|--check) ;;
  *) echo "usage: $(basename "$0") [--check]" >&2; exit 2 ;;
esac
# "<module root>|<bundled spec folder inside the module>|<spec folders to bundle>|<folders to leave out>"
TARGETS=(
  "ios/Packages/InvoiceCore|Sources/InvoiceCore/Resources/spec|tax reference pdf/labels pdf/layout pdf/fonts design|"
  "ios/Packages/InvoiceData|Sources/InvoiceData/Resources/spec|schema/db/migrations|"
  "android/core/domain|src/main/resources/spec|tax reference pdf/labels pdf/layout pdf/fonts design|fonts/*.ttf"
  "android/core/data|src/main/resources/spec|schema/db/migrations|"
)
# Android reads the UI fonts as resources (res/font), whose file names must be lower_snake_case.
ANDROID_FONTS="android/core/designsystem/src/main/res/font"
status=0
for target in "${TARGETS[@]}"; do
  IFS='|' read -r module folder sources leaveOut <<<"$target"
  dest="$module/$folder"
  if [[ ! -d "$ROOT/$module" ]]; then echo "skip: $module (module not created yet)"; continue; fi
  read -r -a SOURCES <<<"$sources"
  EXCLUDES=(--exclude='*.md')
  for skip in $leaveOut; do EXCLUDES+=(--exclude="$skip"); done
  for src in "${SOURCES[@]}"; do
    from="$ROOT/spec/$src"; to="$ROOT/$dest/$src"
    if [[ "$MODE" == "--check" ]]; then
      # A checksum dry run with the same rules as the copy: any line it prints is a file that differs.
      if [[ ! -d "$to" ]] || [[ -n "$(rsync -anci --delete "${EXCLUDES[@]}" "$from/" "$to/" 2>&1)" ]]; then
        echo "out of date: $dest/$src (run make sync-spec)"; status=1
      fi
    else
      mkdir -p "$to"; rsync -a --delete "${EXCLUDES[@]}" "$from/" "$to/"; echo "synced: spec/$src -> $dest/$src"
    fi
  done
done
if [[ -d "$ROOT/android/core/designsystem" ]]; then
  fontDir="$ROOT/$ANDROID_FONTS"
  [[ "$MODE" == "--check" ]] || { rm -rf "$fontDir"; mkdir -p "$fontDir"; }
  for font in "$ROOT"/spec/design/fonts/*.ttf; do
    name="$(basename "$font" .ttf | sed -E 's/([a-z0-9])([A-Z])/\1_\2/g; s/-/_/g' | tr '[:upper:]' '[:lower:]').ttf"
    if [[ "$MODE" == "--check" ]]; then
      cmp -s "$font" "$fontDir/$name" || { echo "out of date: $ANDROID_FONTS/$name (run make sync-spec)"; status=1; }
    else
      cp "$font" "$fontDir/$name"
    fi
  done
  if [[ "$MODE" == "--check" ]]; then
    extra=$(comm -13 <(for f in "$ROOT"/spec/design/fonts/*.ttf; do basename "$f" .ttf | sed -E 's/([a-z0-9])([A-Z])/\1_\2/g; s/-/_/g' | tr '[:upper:]' '[:lower:]'; done | sort) \
      <(ls "$fontDir" 2>/dev/null | sed 's/\.ttf$//' | sort))
    [[ -z "$extra" ]] || { echo "out of date: $ANDROID_FONTS has extra files (run make sync-spec)"; status=1; }
  else
    echo "synced: spec/design/fonts -> $ANDROID_FONTS"
  fi
fi
if [[ "$MODE" == "--check" && $status -eq 0 ]]; then echo "✓ bundled spec copies are up to date"; fi
exit $status
