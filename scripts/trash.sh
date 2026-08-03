#!/usr/bin/env bash
# Move paths to the user trash instead of deleting (spec 5.5).
# Usage: scripts/trash.sh <path>...
# Prints each destination. Timestamped, so nothing is overwritten.
set -Eeuo pipefail
IFS=$'\n\t'

trap 'echo "Command failed at line $LINENO" >&2' ERR

TRASH="$HOME/.local/share/Trash/files"
mkdir -p "$TRASH"

for src in "$@"; do
  [ -e "$src" ] || { echo "not found: $src" >&2; exit 1; }
  dst="$TRASH/$(basename "$src")-$(date +%s)"
  mv "$src" "$dst"
  echo "trashed: $src -> $dst"
done
