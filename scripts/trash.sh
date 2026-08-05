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

    # Reject path-traversal and system paths. The allow-list decision rests on
    # the CANONICAL path (R-03): realpath resolves embedded ../ traversal and
    # symlinked dirs (e.g. /home/nika/linkdir/file where linkdir -> /etc), so
    # /home/nika/../../etc/passwd cannot slip past a /home/* glob. The parent
    # dir must exist; the final component may be a broken symlink (handled by
    # -L above) and is appended unmodified so mv moves the link, not its target.
    case "$src" in
        ..|../*)
            echo "FATAL: Refusing to trash '$src' (parent-path traversal)." >&2
            exit 1
            ;;
    esac
    parent="$(realpath -e -- "$(dirname -- "$src")" 2>/dev/null)" || {
        echo "FATAL: cannot resolve parent of '$src'" >&2
        exit 1
    }
    canon="$parent/$(basename -- "$src")"
    case "$canon" in
        /home/*|/tmp/*|/mnt/*|/media/*) ;;
        *)
            echo "FATAL: Refusing to trash '$src' (resolves to '$canon', outside allowed trees)." >&2
            exit 1
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
