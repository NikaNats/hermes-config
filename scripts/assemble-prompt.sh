#!/usr/bin/env bash
# Assemble the active system prompt from SOUL.md + one persona layer.
# Usage:
#   assemble-prompt.sh                # base only (SOUL.md)
#   assemble-prompt.sh coding         # base + coding persona
#   assemble-prompt.sh review|ops|research|automation
set -euo pipefail

# Hermes' canonical default home is ~/.hermes (hermes_constants.py
# _get_platform_default_hermes_home); HERMES_HOME overrides it when set.
HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
if [ ! -d "$HERMES_HOME" ]; then
    echo "WARN: HERMES_HOME=$HERMES_HOME does not exist." >&2
    echo "      Set HERMES_HOME or run 'hermes setup' first." >&2
fi
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
    AVAILABLE="$(ls "$PROMPT_DIR"/*.md 2>/dev/null | xargs -n1 basename | sed 's/\.md$//' | tr '\n' ' ')"
    echo "Unknown persona: $PERSONA (available: $AVAILABLE)" >&2
    exit 1
  fi
  cat "$HERMES_HOME/SOUL.md" "$PERSONA_FILE" > "$OUT"
else
  cp "$HERMES_HOME/SOUL.md" "$OUT"
fi

echo "Wrote $OUT ($(wc -c < "$OUT") bytes)"
