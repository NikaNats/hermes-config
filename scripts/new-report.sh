#!/usr/bin/env bash
# Create a dated Markdown report artifact (spec 4.5).
# Usage: scripts/new-report.sh <name>
# Prints the created file path; exits 0. If the file already exists,
# prints the existing path to stderr and does not overwrite.
set -Eeuo pipefail
IFS=$'\n\t'

NAME="$(basename -- "${1:-report}" | tr -cd '[:alnum:]_.-')"
[ -z "$NAME" ] && NAME="report"
# R-21: reject degenerate names (".", "..", hidden dotfiles) -> fall back
case "$NAME" in
    .|..|.*) NAME="report" ;;
esac
DIR="$HOME/agent/reports/$(TZ=UTC date +%Y-%m-%d)"
mkdir -p "$DIR"
FILE="$DIR/$NAME.md"

if [ ! -e "$FILE" ]; then
  cp "$(dirname "$0")/templates/report.md" "$FILE"
else
  echo "exists: $FILE" >&2
fi
echo "$FILE"
