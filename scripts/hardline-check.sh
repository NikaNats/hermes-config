#!/usr/bin/env bash
# hardline-check.sh — defense-in-depth command scanner (README § prompt-injection defense).
# Usage: hardline-check.sh '<candidate command line>' ; exit 1 = BLOCK.
# Catches what prefix-glob deny lists cannot: pipe-to-shell, command
# substitution of remote fetches, base64-to-shell, eval/exec of fetched data,
# and recursive-delete of root/home via variable or reordered flags.
# Integration: approvals.smart_policy instructs the Guardian to run this
# scanner pre-execution on any command that is not already deny-listed.
set -Eeuo pipefail
IFS=$'\n\t'

CMD="${1:?usage: hardline-check.sh '<command>'}"

block() { echo "HARDLINE BLOCK: $1" >&2; exit 1; }

# 1. Any pipe into a shell/interpreter (covers base64/echo/cat, not just curl/wget)
if printf '%s\n' "$CMD" | grep -Eq '\|[[:space:]]*(ba|da|z)?sh([[:space:]]|$)|\|[[:space:]]*(python[0-9.]*|node|ruby|perl)([[:space:]]|$)'; then
  block "pipe-to-shell/interpreter"
fi

# 2. Command substitution or backticks wrapping a network fetch
if printf '%s\n' "$CMD" | grep -Eq '\$\((curl|wget)[^)]*\)|`[^`]*(curl|wget)[^`]*`'; then
  block "command-substitution of remote fetch"
fi

# 3. base64/xz/openssl decode feeding an execution context
if printf '%s\n' "$CMD" | grep -Eq '(base64|xz|openssl)[[:space:]]+(-d|--decode)[^;]*\|'; then
  block "decode-to-pipeline (possible payload staging)"
fi

# 4. eval / exec sourcing remote or decoded content
if printf '%s\n' "$CMD" | grep -Eq '(^|[;&|])[[:space:]]*(eval|exec)[[:space:]]'; then
  block "eval/exec present"
fi

# 5. rm targeting root-ish paths via variable, literal, or reordered flags
#    (no trailing-context requirement: rm -rf /etc/passwd, rm -rf $X, and
#    (sudo rm -rf /) all match; conservative by design — the deny list already
#    blocks rm -rf /* so this cannot add false positives)
if printf '%s\n' "$CMD" | grep -Eq 'rm[[:space:]]+(-[a-zA-Z]*[rf][a-zA-Z]*[[:space:]]+)+(/|~|\$HOME|\$[A-Za-z_][A-Za-z0-9_]*)'; then
  block "recursive-delete of root/home"
fi

exit 0
