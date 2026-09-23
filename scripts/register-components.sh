#!/usr/bin/env bash
# Register every COM component (*.ocx / *.dll) found in a directory.
#
# The files are copied into the Wine prefix's system32 first, then regsvr32 is
# run. The location matters: VB6's IDE crashes at startup with
#   "Unexpected error; quitting"
# if a registered component lives outside a system directory, even for a plain
# COM DLL like Chilkat. Failures are non-fatal: not every DLL in a project
# folder is a COM server (e.g. c4fox65.dll is a plain native DLL).
#
# Note: ActiveX *controls* (MSFLXGRD.OCX, MSWINSCK.OCX, …) register fine but
# cannot be instantiated under Wine, so projects whose forms host them still
# will not build.
#
# Usage: register-components.sh [dir]     (default /components)
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIR="${1:-/components}"

if [ ! -d "$DIR" ]; then
  echo "[register] no components directory: $DIR (nothing to register)"
  exit 0
fi

PREFIX_DIR="${WINEPREFIX:-/wine}/drive_c/windows/system32"
mkdir -p "$PREFIX_DIR"

shopt -s nullglob nocaseglob
files=("$DIR"/*.ocx "$DIR"/*.dll)

if [ "${#files[@]}" -eq 0 ]; then
  echo "[register] no *.ocx/*.dll in $DIR"
  exit 0
fi

for f in "${files[@]}"; do
  base="$(basename "$f")"
  cp -f "$f" "$PREFIX_DIR/$base"
  # regsvr32 must run with a display; without one the registration is written
  # half-complete and the VB6 IDE then dies with "Unexpected error; quitting".
  if ( cd "$PREFIX_DIR" && xvfb-run -a wine regsvr32 /s "$base" ) >/dev/null 2>&1; then
    echo "[register]   ok      $base"
  else
    echo "[register]   skipped $base (not a COM server)"
  fi
done
