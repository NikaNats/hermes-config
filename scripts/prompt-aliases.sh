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

# Cat the persona file, aborting (and listing options) if it is missing so a
# typo never silently degrades to an empty HERMES_EPHEMERAL_SYSTEM_PROMPT.
_persona_env() {
    local file="$HERMES_PROMPTS_DIR/$1.md"
    if [ ! -f "$file" ]; then
        echo "FATAL: Persona file missing: $file" >&2
        echo "       Available: $(ls "$HERMES_PROMPTS_DIR"/*.md 2>/dev/null | xargs -n1 basename | sed 's/\.md$//' | tr '\n' ' ')" >&2
        return 1
    fi
    cat "$file"
}

hermes-base()       { hermes chat; }
hermes-coding()     { _validate_persona "coding"     || return 1; local p; p="$(_persona_env coding)"     || return 1; HERMES_EPHEMERAL_SYSTEM_PROMPT="$p"     hermes chat; }
hermes-review()     { _validate_persona "review"     || return 1; local p; p="$(_persona_env review)"     || return 1; HERMES_EPHEMERAL_SYSTEM_PROMPT="$p"     hermes chat; }
hermes-ops()        { _validate_persona "ops"        || return 1; local p; p="$(_persona_env ops)"        || return 1; HERMES_EPHEMERAL_SYSTEM_PROMPT="$p"        hermes chat; }
hermes-research()   { _validate_persona "research"   || return 1; local p; p="$(_persona_env research)"   || return 1; HERMES_EPHEMERAL_SYSTEM_PROMPT="$p"   hermes chat; }
hermes-automation() { _validate_persona "automation" || return 1; local p; p="$(_persona_env automation)" || return 1; HERMES_EPHEMERAL_SYSTEM_PROMPT="$p" hermes chat; }
hermes-production() { _validate_persona "production" || return 1; local p; p="$(_persona_env production)" || return 1; HERMES_EPHEMERAL_SYSTEM_PROMPT="$p" hermes chat; }

# One-shot variant: hermes-one coding "build the auth module"
hermes-one() {
  local persona="${1:?usage: hermes-one <persona|base> <query>}"
  shift
  if [ "$persona" = "base" ]; then
    hermes chat -Q -q "$*"
  else
    _validate_persona "$persona" || return 1
    local p
    p="$(_persona_env "$persona")" || return 1
    HERMES_EPHEMERAL_SYSTEM_PROMPT="$p" hermes chat -Q -q "$*"
  fi
}
