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
# "<module root>|<bundled spec folder inside the module>|<spec folders to bundle>"
TARGETS=(
  "ios/Packages/InvoiceCore|Sources/InvoiceCore/Resources/spec|tax reference pdf/labels pdf/layout pdf/fonts design"
  "ios/Packages/InvoiceData|Sources/InvoiceData/Resources/spec|schema/db/migrations"
  "android/core/domain|src/main/resources/spec|tax reference pdf/labels pdf/layout pdf/fonts design"
  "android/core/data|src/main/resources/spec|schema/db/migrations"
)
status=0
for target in "${TARGETS[@]}"; do
  IFS='|' read -r module folder sources <<<"$target"
  dest="$module/$folder"
  if [[ ! -d "$ROOT/$module" ]]; then echo "skip: $module (module not created yet)"; continue; fi
  read -r -a SOURCES <<<"$sources"
  for src in "${SOURCES[@]}"; do
    from="$ROOT/spec/$src"; to="$ROOT/$dest/$src"
    if [[ "$MODE" == "--check" ]]; then
      if ! diff -rq --exclude='*.md' "$from" "$to" >/dev/null 2>&1; then
        echo "out of date: $dest/$src (run make sync-spec)"; status=1
      fi
    else
      mkdir -p "$to"; rsync -a --delete --exclude='*.md' "$from/" "$to/"; echo "synced: spec/$src -> $dest/$src"
    fi
  done
done
if [[ "$MODE" == "--check" && $status -eq 0 ]]; then echo "✓ bundled spec copies are up to date"; fi
exit $status
