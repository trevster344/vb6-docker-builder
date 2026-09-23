#!/usr/bin/env bash
# Ensure the standard VB6 SP6 control/runtime set is registered, so arbitrary
# projects load. Extracts the redistributable CABs shipped with SP6 and
# registers the OCX/ActiveX DLLs they contain.
#
# Usage: register-base.sh [sp6-dir]     (default /media/sp6)
set -uo pipefail

SP6_DIR="${1:-/media/sp6}"
WORK="$(mktemp -d)"
PREFIX_DIR="${WINEPREFIX:-/wine}/drive_c/windows/system32"
mkdir -p "$PREFIX_DIR"

if [ ! -d "$SP6_DIR" ]; then
  echo "[base] no SP6 dir: $SP6_DIR"
  exit 0
fi

echo "[base] extracting redistributable CABs from $SP6_DIR"
shopt -s nullglob nocaseglob
for cab in "$SP6_DIR"/*.cab; do
  cabextract -q -d "$WORK" "$cab" >/dev/null 2>&1 || true
done

shopt -s nullglob nocaseglob
components=("$WORK"/*.ocx "$WORK"/*.dll)
echo "[base] registering ${#components[@]} extracted component(s)"
for f in "${components[@]}"; do
  base="$(basename "$f")"
  cp -f "$f" "$PREFIX_DIR/$base"
  ( cd "$PREFIX_DIR" && xvfb-run -a wine regsvr32 /s "$base" ) >/dev/null 2>&1 \
    && echo "[base]   ok      $base" \
    || true
done

rm -rf "$WORK"
echo "[base] done"
