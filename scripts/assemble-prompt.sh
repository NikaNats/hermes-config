#!/usr/bin/env bash
# Assemble the active system prompt from SOUL.md + one persona layer.
# Usage:
#   assemble-prompt.sh                # base only (SOUL.md)
#   assemble-prompt.sh coding         # base + coding persona
#   assemble-prompt.sh review|ops|research|automation
set -euo pipefail

HERMES_HOME="${HERMES_HOME:-$HOME/.config/hermes}"
PROMPT_DIR="${HERMES_PROMPT_DIR:-$HERMES_HOME/prompts}"
CACHE_DIR="${HERMES_CACHE_DIR:-$HERMES_HOME/cache}"
OUT="$CACHE_DIR/active-system-prompt.md"
PERSONA="${1:-}"

mkdir -p "$CACHE_DIR"

if [[ -n "$PERSONA" ]]; then
  # Strict allow-list: blocks path traversal (../../etc/...) and injection
  if [[ ! "$PERSONA" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    echo "FATAL: Invalid persona name '$PERSONA'. Must match ^[a-zA-Z0-9_-]+$" >&2
    exit 1
  fi
  PERSONA_FILE="$PROMPT_DIR/$PERSONA.md"
  if [[ ! -f "$PERSONA_FILE" ]]; then
    echo "Unknown persona: $PERSONA (available: base coding review ops research automation)" >&2
    exit 1
  fi
  cat "$HERMES_HOME/SOUL.md" "$PERSONA_FILE" > "$OUT"
else
  cp "$HERMES_HOME/SOUL.md" "$OUT"
fi

echo "Wrote $OUT ($(wc -c < "$OUT") bytes)"
