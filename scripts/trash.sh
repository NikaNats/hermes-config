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
    # Handle broken symlinks: -e follows symlinks, -L checks the link itself
    if [ ! -e "$src" ] && [ ! -L "$src" ]; then
        echo "not found: $src" >&2
        exit 1
    fi

    # Reject path-traversal and system paths. Absolute paths are allowed only
    # under user-writable trees (home, temp, mounts); everything else is
    # refused so a mistyped /etc/... target can't be moved out of place.
    case "$src" in
        ..|../*)
            echo "FATAL: Refusing to trash '$src' (parent-path traversal)." >&2
            exit 1
            ;;
        /*)
            case "$src" in
                /home/*|/tmp/*|/mnt/*|/media/*) ;;
                *)
                    echo "FATAL: Refusing to trash '$src' (system path)." >&2
                    exit 1
                    ;;
            esac
            ;;
    esac

    # Nanosecond precision + collision loop
    ts="$(date +%s%N)"
    base="$TRASH/$(basename -- "$src")-$ts"
    dst="$base"
    counter=0

    while [ -e "$dst" ] || [ -L "$dst" ]; do
        counter=$((counter + 1))
        dst="${base}-${counter}"
    done

    mv -- "$src" "$dst"
    echo "trashed: $src -> $dst"
done
