#!/usr/bin/env bash
# Populate media/ from a local Visual Studio 6 / VB6 media tree.
#
# Defaults to the parent directory of this repo (the repo is expected to live
# inside the VB6 media folder, e.g. D:\PegasusNet - Trev Local\VB6\vb6-builder).
# Override with VB6_MEDIA_SOURCE in .env (see env.example) or --source.
#
#   media/cd/   <- <source>/vb6studio_disk1  (pruned to the VB6 install subset)
#   media/sp6/  <- <source>/VB6_Services_Packs/vs6sp6setup
#
# Usage:
#   ./scripts/prepare-media.sh [--source <dir>] [--force]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Local overrides: source .env if present (VB6_MEDIA_SOURCE).
[ -f "$REPO_DIR/.env" ] && { set -a; . "$REPO_DIR/.env"; set +a; }

SOURCE="${VB6_MEDIA_SOURCE:-$REPO_DIR/..}"
FORCE=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --source) SOURCE="$2"; shift 2 ;;
    --force)  FORCE=1; shift ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

CD_SRC="$SOURCE/vb6studio_disk1"
SP6_SRC="$SOURCE/VB6_Services_Packs/vs6sp6setup"
CD_DST="$REPO_DIR/media/cd"
SP6_DST="$REPO_DIR/media/sp6"

[ -d "$CD_SRC" ]  || { echo "ERROR: not found: $CD_SRC"  >&2; exit 1; }
[ -d "$SP6_SRC" ] || { echo "ERROR: not found: $SP6_SRC" >&2; exit 1; }

# NOTE: the whole disk is copied. The ACME setup table (VB6.STF) references
# files across VC98 / VFP98 / OS / COMMON / … — pruning any of them makes the
# setup abort with exit 7 and an incomplete install.

log() { echo "[prepare-media] $*"; }

# Copy a directory tree into an existing destination.
#
# MSYS/Git-Bash cp mishandles the VS6 disk: it collides case-insensitively on
# entries like SETUP/ (directory) and SETUP.EXE (file), and fails with
# "cannot overwrite non-directory ... with directory". On Windows we therefore
# hand the copy to PowerShell; elsewhere plain cp is fine.
copy_tree() {
  local src="$1" dst="$2"
  case "$(uname -s 2>/dev/null || echo unknown)" in
    MINGW*|MSYS*|CYGWIN*)
      if command -v powershell >/dev/null 2>&1; then
        powershell -NoProfile -Command \
          "Copy-Item -Path '$(cygpath -w "$src")\*' -Destination '$(cygpath -w "$dst")' -Recurse -Force"
        return $?
      fi
      ;;
  esac
  cp -a "$src/." "$dst/"
}

# Clear the read-only bit the CD files carry, otherwise rm/cp fail on Windows.
unlock() {
  local d="$1"
  [ -d "$d" ] || return 0
  chmod -R u+w "$d" 2>/dev/null || true
}

if [ "$FORCE" = 1 ]; then
  unlock "$CD_DST"; unlock "$SP6_DST"
  rm -rf "$CD_DST" "$SP6_DST"
fi

log "source: $SOURCE"

mkdir -p "$CD_DST" "$SP6_DST"

log "cd/ (full disk)"
copy_tree "$CD_SRC" "$CD_DST"

log "sp6/ (full)"
copy_tree "$SP6_SRC" "$SP6_DST"

log "done."
log "  cd : $(du -sh "$CD_DST" 2>/dev/null | cut -f1)"
log "  sp6: $(du -sh "$SP6_DST" 2>/dev/null | cut -f1)"
