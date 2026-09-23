#!/usr/bin/env bash
# Build the vb6-builder image.
#
#   ./build.sh [tag]        (default tag: vb6-builder:sp6)
#
# Requires media/cd and media/sp6 to be populated; run scripts/prepare-media.sh
# first if they are empty.
set -euo pipefail
cd "$(dirname "$0")"

TAG="${1:-vb6-builder:sp6}"

for d in media/cd media/sp6; do
  if [ ! -d "$d" ] || [ -z "$(ls -A "$d" 2>/dev/null)" ]; then
    echo "ERROR: $d is missing or empty." >&2
    echo "       Run scripts/prepare-media.sh to populate it from the local media." >&2
    exit 1
  fi
done

echo "Building $TAG ..."
exec docker build -t "$TAG" .
