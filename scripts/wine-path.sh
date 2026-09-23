#!/usr/bin/env bash
# Convert a POSIX path to a Wine (Windows) path.
# Wine maps the filesystem root "/" to "Z:\", so /work/x.vbp -> Z:\work\x.vbp
set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "usage: wine-path.sh <posix-path>" >&2
  exit 2
fi

# Normalise backslashes to forward slashes, then flip to backslashes.
printf 'Z:%s' "$(printf '%s' "$1" | tr '\\' '/' | sed 's#/#\\#g')"
