#!/usr/bin/env bash
# Move paths to the user trash instead of deleting (R4).
# Changes vs R-03: /mnt & /media removed from default allowlist (opt-in
# TRASH_ALLOW_MOUNTS=1); size guard (TRASH_MAX_BYTES, default 1 GiB);
# cross-device mv refusal (opt-in TRASH_ALLOW_XDEV=1); double canonical-path
# check against TOCTOU.
set -Eeuo pipefail
IFS=$'\n\t'
trap 'echo "Command failed at line $LINENO" >&2' ERR
die() { echo "FATAL: $*" >&2; exit 1; }

TRASH="$HOME/.local/share/Trash/files"
mkdir -p "$TRASH"
MAX_BYTES="${TRASH_MAX_BYTES:-1073741824}"   # 1 GiB

ALLOWED_ROOTS=(/home /tmp)
[ "${TRASH_ALLOW_MOUNTS:-0}" = "1" ] && ALLOWED_ROOTS+=(/mnt /media)

for src in "$@"; do
  if [ ! -e "$src" ] && [ ! -L "$src" ]; then echo "not found: $src" >&2; exit 1; fi
  case "$src" in ..|../*) die "refusing to trash '$src' (parent-path traversal)";; esac

  parent="$(realpath -e -- "$(dirname -- "$src")" 2>/dev/null)" || die "cannot resolve parent of '$src'"
  canon="$parent/$(basename -- "$src")"

  ok=""
  for r in "${ALLOWED_ROOTS[@]}"; do case "$canon" in "$r"|"$r"/*) ok=1;; esac; done
  [ -n "$ok" ] || die "refusing to trash '$src' (resolves to '$canon', outside allowed trees: ${ALLOWED_ROOTS[*]})"

  # Size guard (du -sb works on dirs and files alike). Timeout + fail-closed:
  # if the tree cannot be sized in 30s, refuse rather than guess.
  size="$(timeout 30 du -sb -- "$src" 2>/dev/null | cut -f1)" || die "cannot size '$src' (du failed or timed out)"
  size="${size:-0}"
  if [ "$size" -gt "$MAX_BYTES" ] && [ "${TRASH_FORCE:-0}" != "1" ]; then
    die "refusing to trash '$src': $size bytes exceeds TRASH_MAX_BYTES=$MAX_BYTES (override: TRASH_FORCE=1)"
  fi

  # Cross-device guard: mv across filesystems is copy+unlink — not a safe trash op.
  # tmpfs sources (e.g. systemd /tmp) are EXEMPT: the copy+unlink is fast and
  # RAM-backed, so the guard's cost/risk rationale does not apply. Real mounts
  # (drvfs /mnt, other disks) stay refused unless TRASH_ALLOW_XDEV=1.
  srcdev="$(stat -c %d -- "$src" 2>/dev/null || true)"
  trashdev="$(stat -c %d -- "$TRASH")"
  SRC_FSTYPE="$(findmnt -T "$src" -o FSTYPE -n 2>/dev/null || true)"
  if [ -n "$srcdev" ] && [ "$srcdev" != "$trashdev" ] && [ "$SRC_FSTYPE" != "tmpfs" ] && [ "${TRASH_ALLOW_XDEV:-0}" != "1" ]; then
    die "refusing to trash '$src': cross-device move (would copy+unlink). Override: TRASH_ALLOW_XDEV=1"
  fi

  ts="$(date +%s%N)"
  base="$TRASH/$(basename -- "$src")-$ts"
  dst="$base"; counter=0
  while [ -e "$dst" ] || [ -L "$dst" ]; do
    counter=$((counter + 1)); dst="${base}-${counter}"
  done

  # Re-canonicalize immediately before mv; refuse if the target moved under us
  parent2="$(realpath -e -- "$(dirname -- "$src")" 2>/dev/null || true)"
  [ "$parent2/$(basename -- "$src")" = "$canon" ] || die "path changed under us: '$src' — aborting"

  mv -- "$src" "$dst"
  echo "trashed: $src -> $dst"
done
