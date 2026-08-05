#!/usr/bin/env bash
# Move paths to the user trash instead of deleting (spec 5.5).
# Usage: scripts/trash.sh <path>...
# Prints each destination. Nanosecond timestamp + collision loop, so nothing
# is ever silently overwritten (fixes same-second mv collisions).
set -Eeuo pipefail
IFS=$'\n\t'
trap 'echo "Command failed at line $LINENO" >&2' ERR

TRASH="$HOME/.local/share/Trash/files"
mkdir -p "$TRASH"

for src in "$@"; do
    [ -e "$src" ] || { echo "not found: $src" >&2; exit 1; }

    # Nanosecond precision + collision loop
    ts="$(date +%s%N)"
    base="$TRASH/$(basename -- "$src")-$ts"
    dst="$base"
    counter=0

    while [ -e "$dst" ]; do
        counter=$((counter + 1))
        dst="${base}-${counter}"
    done

    mv -- "$src" "$dst"
    echo "trashed: $src -> $dst"
done
