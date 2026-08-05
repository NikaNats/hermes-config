#!/usr/bin/env bash
# Persona activation helpers (v1.1).
# Source this file from ~/.bashrc:
#   [ -f ~/src/hermes-config/scripts/prompt-aliases.sh ] && source ~/src/hermes-config/scripts/prompt-aliases.sh
#
# How it works (verified against Hermes v0.19.1 source, 2026-08-03):
#   - There is NO `hermes --system-prompt` CLI flag. The supported mechanism is
#     the HERMES_EPHEMERAL_SYSTEM_PROMPT env var, read at session init
#     (cli.py: HERMES_EPHEMERAL_SYSTEM_PROMPT -> agent.system_prompt config).
#   - It is injected as the CONTEXT tier, ON TOP of SOUL.md (stable identity tier),
#     so each function feeds the persona diff only — SOUL.md is already loaded.
#   - Verified end-to-end: a marker string set via the env var was echoed back by
#     the model in a real session.
#   - Alternative (persistent, in-session): register entries under
#     agent.personalities in config.yaml, then use the /personality <name> command.

# Resolve prompts dir relative to this file so the aliases survive any clone
# location; fall back to the canonical path if the layout is unusual.
_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HERMES_PROMPTS_DIR="${HERMES_PROMPTS_DIR:-$(dirname "$_SCRIPT_DIR")/prompts}"
[ -d "$HERMES_PROMPTS_DIR" ] || HERMES_PROMPTS_DIR="$HOME/src/hermes-config/prompts"

_validate_persona() {
    [[ "$1" =~ ^[a-zA-Z0-9_-]+$ ]] || { echo "FATAL: Invalid persona: $1" >&2; return 1; }
}

hermes-base()       { hermes chat; }
hermes-coding()     { _validate_persona "coding" && HERMES_EPHEMERAL_SYSTEM_PROMPT="$(cat "$HERMES_PROMPTS_DIR/coding.md")"     hermes chat; }
hermes-review()     { _validate_persona "review" && HERMES_EPHEMERAL_SYSTEM_PROMPT="$(cat "$HERMES_PROMPTS_DIR/review.md")"     hermes chat; }
hermes-ops()        { _validate_persona "ops" && HERMES_EPHEMERAL_SYSTEM_PROMPT="$(cat "$HERMES_PROMPTS_DIR/ops.md")"        hermes chat; }
hermes-research()   { _validate_persona "research" && HERMES_EPHEMERAL_SYSTEM_PROMPT="$(cat "$HERMES_PROMPTS_DIR/research.md")"   hermes chat; }
hermes-automation() { _validate_persona "automation" && HERMES_EPHEMERAL_SYSTEM_PROMPT="$(cat "$HERMES_PROMPTS_DIR/automation.md")" hermes chat; }
hermes-production() { _validate_persona "production" && HERMES_EPHEMERAL_SYSTEM_PROMPT="$(cat "$HERMES_PROMPTS_DIR/production.md")" hermes chat; }

# One-shot variant: hermes-one coding "build the auth module"
hermes-one() {
  local persona="${1:?usage: hermes-one <persona|base> <query>}"
  shift
  if [ "$persona" = "base" ]; then
    hermes chat -Q -q "$*"
  else
    _validate_persona "$persona" || return 1
    HERMES_EPHEMERAL_SYSTEM_PROMPT="$(cat "$HERMES_PROMPTS_DIR/$persona.md")" hermes chat -Q -q "$*"
  fi
}
