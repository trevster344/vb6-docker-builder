#!/usr/bin/env bash
# Build the vb6-builder image.
#
#   ./build.sh [tag]                         (default tag: vb6-builder:sp6)
#   ./build.sh --cd <dir> --sp6 <dir>        (point at media directly)
#
# The CD and SP6 install media are supplied as named build contexts. Defaults:
# media/cd and media/sp6 (stage them via scripts/prepare-media.sh). To skip the
# staging copy, set VB6_CD / VB6_SP6 in .env (see env.example) or pass --cd/--sp6.
set -euo pipefail
cd "$(dirname "$0")"

# Local overrides: source .env if present (VB6_CD / VB6_SP6).
[ -f .env ] && { set -a; . ./.env; set +a; }

TAG="vb6-builder:sp6"
CD_CTX="${VB6_CD:-media/cd}"
SP6_CTX="${VB6_SP6:-media/sp6}"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --cd)       CD_CTX="$2"; shift 2 ;;
    --sp6|--sp) SP6_CTX="$2"; shift 2 ;;
    -h|--help)  sed -n '2,16p' "$0"; exit 0 ;;
    *)          TAG="$1"; shift ;;
  esac
done

for ctx in "$CD_CTX" "$SP6_CTX"; do
  if [ ! -d "$ctx" ] || [ -z "$(ls -A "$ctx" 2>/dev/null)" ]; then
    echo "ERROR: '$ctx' is missing or empty." >&2
    echo "       Populate media/cd + media/sp6 (scripts/prepare-media.sh) or" >&2
    echo "       set VB6_CD/VB6_SP6 in .env (see env.example) or pass --cd/--sp6." >&2
    exit 1
  fi
done

echo "Building $TAG ..."
echo "  cd : $CD_CTX"
echo "  sp6: $SP6_CTX"
exec docker build -t "$TAG" \
  --build-context "cd=$CD_CTX" \
  --build-context "sp6=$SP6_CTX" \
  .
