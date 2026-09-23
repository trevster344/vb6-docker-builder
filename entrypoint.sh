#!/usr/bin/env bash
# Project-agnostic VB6 build driver.
#
# Inputs (env):
#   VBP_PATH               dir containing the .vbp            (default /work)
#   VBP_NAME               project file name, e.g. My.vbp     (default: auto-discover)
#   VBP_OUTPUT             output EXE name                    (default: ExeName32)
#   VBP_OUTDIR             VB6 /outdir (compiler output dir)  (default: scratch dir)
#   VBP_DEFINES            conditional compilation, name=value[,..]
#   VBP_EXTRA_COMPONENTS   dir of .ocx/.dll to register       (default /components)
#   VBP_COLLECT            where the final EXE is copied      (default /out)
#   VBP_SCRATCH            writable build copy                (default /build)
set -uo pipefail

VBP_PATH="${VBP_PATH:-/work}"
VBP_NAME="${VBP_NAME:-}"
VBP_OUTPUT="${VBP_OUTPUT:-}"
VBP_OUTDIR="${VBP_OUTDIR:-}"
VBP_DEFINES="${VBP_DEFINES:-}"
VBP_EXTRA_COMPONENTS="${VBP_EXTRA_COMPONENTS:-/components}"
VBP_COLLECT="${VBP_COLLECT:-/out}"
VBP_SCRATCH="${VBP_SCRATCH:-/build}"

export WINEPREFIX="${WINEPREFIX:-/wine}"
export WINEARCH="${WINEARCH:-win64}"
export WINEDEBUG="${WINEDEBUG:--all}"
export DISPLAY="${DISPLAY:-:99}"

BIN="/usr/local/bin"
log() { echo "[build] $*"; }
winpath() { "$BIN/wine-path.sh" "$1"; }

find_vb6() {
  for p in \
    "$WINEPREFIX/drive_c/Program Files (x86)/Microsoft Visual Studio/VB98/VB6.EXE" \
    "$WINEPREFIX/drive_c/Program Files/Microsoft Visual Studio/VB98/VB6.EXE" \
    "$WINEPREFIX/drive_c/VB6/VB6.EXE"; do
    [ -f "$p" ] && { echo "$p"; return 0; }
  done
  return 1
}

VB6="$(find_vb6)" || { log "ERROR: VB6.EXE not found in the image"; exit 1; }
log "VB6: $VB6"

# --- resolve the project ----------------------------------------------------
if [ -n "$VBP_NAME" ]; then
  VBP_FILE="$VBP_PATH/$VBP_NAME"
else
  mapfile -t found < <(find "$VBP_PATH" -maxdepth 2 -iname "*.vbp" 2>/dev/null)
  if [ "${#found[@]}" -ne 1 ]; then
    log "ERROR: set VBP_NAME — found ${#found[@]} .vbp file(s) under $VBP_PATH"
    exit 1
  fi
  VBP_FILE="${found[0]}"
fi
[ -f "$VBP_FILE" ] || { log "ERROR: project not found: $VBP_FILE"; exit 1; }
log "project: $VBP_FILE"

# --- scratch copy (source mount stays read-only) ----------------------------
rm -rf "$VBP_SCRATCH"
mkdir -p "$VBP_SCRATCH"
cp -Rf "$VBP_PATH/." "$VBP_SCRATCH/"
PROJ="$VBP_SCRATCH/$(basename "$VBP_FILE")"

# --- project-specific components --------------------------------------------
"$BIN/register-components.sh" "$VBP_EXTRA_COMPONENTS"

# --- neutralise machine-specific build settings -----------------------------
# Path32 is the directory VB6 writes its intermediate .OBJ files to. A project
# saved on a developer machine often points it at a UNC share or a path that
# does not exist here, which fails the link step with
#   fatal error C1083: Cannot open compiler generated file: '\\host\...\X.OBJ'
# Repoint it at the writable scratch copy.
if grep -qiE '^Path32=' "$PROJ"; then
  WP="$(winpath "$VBP_SCRATCH")"
  # sed treats \b etc. in the replacement as escapes, so double the backslashes.
  WP_ESC="${WP//\\/\\\\}"
  sed -i "s|^Path32=.*|Path32=\"$WP_ESC\"|I" "$PROJ"
  log "Path32 -> $WP"
fi

# --- build ------------------------------------------------------------------
ARGS=(/make "$(winpath "$PROJ")" /out "$(winpath "$VBP_SCRATCH/build.log")")
if [ -n "$VBP_OUTDIR" ]; then
  mkdir -p "$VBP_OUTDIR"
  ARGS+=(/outdir "$(winpath "$VBP_OUTDIR")")
fi
if [ -n "$VBP_DEFINES" ]; then
  IFS=',' read -ra _defs <<< "$VBP_DEFINES"
  for d in "${_defs[@]}"; do ARGS+=(/d "$d"); done
fi

log "compiling"
cd "$WINEPREFIX/drive_c" || exit 1
xvfb-run -a wine "$(winpath "$VB6")" "${ARGS[@]}"
rc=$?

LOG_FILE="$VBP_SCRATCH/build.log"
[ -f "$LOG_FILE" ] && sed 's/\r$//' "$LOG_FILE" | sed 's/^/[vb6] /'

# --- verify -----------------------------------------------------------------
if [ "$rc" -ne 0 ]; then
  log "ERROR: vb6 /make exited $rc"
  exit 1
fi
if [ -f "$LOG_FILE" ] && grep -qiE "compile error|errors during|error [0-9]+" "$LOG_FILE"; then
  log "ERROR: build log reports errors"
  exit 1
fi

# --- locate + collect the EXE ----------------------------------------------
EXE_NAME="$(grep -iE '^ExeName32=' "$PROJ" | head -1 | cut -d= -f2- | tr -d '"\r')"
SEARCH_DIR="${VBP_OUTDIR:-$VBP_SCRATCH}"
CAND=""
if [ -n "$EXE_NAME" ] && [ -f "$SEARCH_DIR/$EXE_NAME" ]; then
  CAND="$SEARCH_DIR/$EXE_NAME"
else
  CAND="$(find "$SEARCH_DIR" -maxdepth 1 -iname "*.exe" -newer "$PROJ" 2>/dev/null | head -1)"
fi
[ -n "$CAND" ] && [ -f "$CAND" ] || { log "ERROR: no output EXE produced"; exit 1; }

mkdir -p "$VBP_COLLECT"
OUT_NAME="${VBP_OUTPUT:-$(basename "$CAND")}"
cp -f "$CAND" "$VBP_COLLECT/$OUT_NAME"
log "OK -> $VBP_COLLECT/$OUT_NAME ($(wc -c < "$VBP_COLLECT/$OUT_NAME") bytes)"
