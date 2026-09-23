#!/usr/bin/env bash
# Install VB6 (VS6 Enterprise) + SP6 into the Wine prefix, unattended.
#
# Recipe based on telyn/docker-vb6 (verified working under WineHQ stable).
#
# What matters (learned the hard way):
#   * WINEARCH=win32                       (VB6 is 32-bit)
#   * the FULL CD must be staged           (the setup table references VC98/VFP98/OS/…)
#   * SETUP/ contents at the SOURCE ROOT next to ACMSETUP.exe
#   * the setup table named ACMSETUP.STF next to ACMSETUP.exe
#   * wine regedit /s KEY.DAT              (sets the "wizard already run" flag)
#   * wine ACMSETUP.exe /n Container /o None /qnt
#   * NO product key required              (the CD's SETUP.INI carries the PID)
#   * the setup may pop a non-fatal "Setup Error Message" dialog -> watchdog
#
# Usage: install-vb6.sh [cd-dir] [sp6-dir]   (defaults /media/cd /media/sp6)
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CD="${1:-/media/cd}"
SP6="${2:-/media/sp6}"

export WINEPREFIX="${WINEPREFIX:-/wine}"
export WINEARCH="${WINEARCH:-win32}"
export WINEDEBUG="${WINEDEBUG:--all}"
export DISPLAY="${DISPLAY:-:99}"
# Disable the Wine Mono/Gecko install prompts (they block wineboot when the
# build has network access and no one is there to click "Cancel").
export WINEDLLOVERRIDES="mscoree,mshtml="

STF_LOCAL="${VBP_STF:-$SCRIPT_DIR/../vendor/telyn_VB6.STF}"
KEY="${VBP_PRODUCT_KEY:-}"

log() { echo "[install-vb6] $*"; }

[ -f "$STF_LOCAL" ] || { log "ERROR: STF not found: $STF_LOCAL"; exit 1; }
[ -d "$CD/SETUP" ] || { log "ERROR: no SETUP/ under $CD"; exit 1; }

winpath() { "$SCRIPT_DIR/wine-path.sh" "$1"; }

# --- X server (the ACME setup is a GUI app) ---------------------------------
Xvfb :99 -screen 0 1024x768x24 >/tmp/xvfb.log 2>&1 &
XVFB_PID=$!
sleep 2

# --- dismiss the non-fatal setup error dialog -------------------------------
dismiss_dialogs() {
  command -v xdotool >/dev/null 2>&1 || return 0
  while true; do
    for w in $(xdotool search --name "Setup Error Message" 2>/dev/null); do
      xdotool windowactivate --sync "$w" 2>/dev/null || true
      xdotool key --window "$w" Return 2>/dev/null || true
    done
    sleep 1
  done
}
dismiss_dialogs &
WATCHDOG_PID=$!
trap 'kill $WATCHDOG_PID $XVFB_PID 2>/dev/null || true' EXIT

# --- wine prefix ------------------------------------------------------------
log "wineboot"
wineboot -u >/dev/null 2>&1

# --- stage the media the way acmsetup expects -------------------------------
VS=/vs
rm -rf "$VS"
mkdir -p "$VS"
cp -R "$CD/." "$VS/"                  # full CD at the source root
cp -R "$CD/SETUP/." "$VS/"            # SETUP contents alongside ACMSETUP.exe
cp -f "$STF_LOCAL" "$VS/ACMSETUP.STF"

log "importing KEY.DAT (wizard-already-run flag)"
[ -f "$VS/KEY.DAT" ] && wine regedit /s "$(winpath "$VS/KEY.DAT")" >/dev/null 2>&1 || true

# --- install VB6 ------------------------------------------------------------
ARGS=(/n "Container" /o "None" /qnt)
[ -n "$KEY" ] && ARGS+=(/k "$KEY")

log "running VB6 setup (silent; dialogs auto-dismissed)"
cd "$VS" || exit 1
timeout 1500 wine "$(winpath "$VS/ACMSETUP.exe")" "${ARGS[@]}" >/tmp/vb6setup.log 2>&1
rc=$?
log "VB6 setup exit=$rc"

VB6="/wine/drive_c/Program Files/Microsoft Visual Studio/VB98/VB6.EXE"
if [ ! -f "$VB6" ]; then
  log "ERROR: VB6.EXE not found after setup. Tail of log:"
  tail -n 40 /tmp/vb6setup.log || true
  exit 1
fi
log "VB6 installed: $VB6"

# --- VB6 runtime (the setup does not always place msvbvm60.dll) -------------
SYS32="/wine/drive_c/windows/system32"
if [ ! -f "$SYS32/msvbvm60.dll" ]; then
  # The runtime ships on the CD under OS/SYSTEM.
  if [ -f "$CD/OS/SYSTEM/MSVBVM60.DLL" ]; then
    log "installing msvbvm60.dll from the CD"
    cp -f "$CD/OS/SYSTEM/MSVBVM60.DLL" "$SYS32/msvbvm60.dll"
    wine regsvr32 /s "C:\\windows\\system32\\msvbvm60.dll" >/dev/null 2>&1 || true
  else
    log "msvbvm60.dll missing; installing via winetricks vb6run"
    winetricks -q vb6run >/tmp/vb6run.log 2>&1 || log "WARN: vb6run exit $?"
  fi
fi

# --- Service Pack 6 ---------------------------------------------------------
SP6_STF_FILE="$(ls "$SP6"/*.stf 2>/dev/null | head -1)"
if [ -n "$SP6_STF_FILE" ]; then
  log "applying SP6 ($(basename "$SP6_STF_FILE"))"
  cp -R "$SP6/." "$VS/" 2>/dev/null || true
  cp -f "$SP6_STF_FILE" "$VS/ACMSETUP.STF"
  timeout 600 wine "$(winpath "$VS/acmsetup.exe")" /n "Container" /o "None" /qnt >/tmp/sp6.log 2>&1
  log "SP6 exit=$?"
else
  log "WARN: no .stf found in $SP6 — skipping SP6"
fi

# --- finalize: restore OLE Automation --------------------------------------
# The VB6 setup leaves the prefix without a working oleaut32.dll (the file is
# missing from system32), which breaks LoadTypeLib on DLL-embedded type
# libraries. Registering any OCX then makes the IDE fail on every build with
# "Unexpected error; quitting". clewarekft's recipe fixes this in a separate
# finalize step; do the same here.
log "finalize: restoring ole32/oleaut32 (required for OCX type libraries)"
winecfg /v win10 >/dev/null 2>&1 || true
winetricks -q --force ole32 oleaut32 >/tmp/oleaut.log 2>&1 || log "WARN: oleaut32 exit $?"
winecfg /v win10 >/dev/null 2>&1 || true
wineboot -u >/dev/null 2>&1 || true

if [ -f "$SYS32/oleaut32.dll" ]; then
  log "oleaut32.dll present: $(stat -c%s "$SYS32/oleaut32.dll") bytes"
else
  log "WARN: oleaut32.dll still missing after finalize"
fi

log "done."
