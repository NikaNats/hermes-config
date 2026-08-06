#!/usr/bin/env bash
# hardline-check.sh — defense-in-depth command scanner (R4 rewrite).
# Usage: hardline-check.sh '<candidate command line>'   (or unquoted args)
# Exit 1 = BLOCK. Fail-closed: this scanner is invoked by smart_policy rule 9;
# if it cannot run, the Guardian must treat the command as BLOCKED.
set -Eeuo pipefail
IFS=$'\n\t'

# Join all args (fixes truncation when the Guardian forgets quoting) and
# flatten newlines to spaces so cross-line pipes/chains are still scanned.
CMD="${*:?usage: hardline-check.sh '<command>'}"
CMD="$(printf '%s\n' "$CMD" | tr '\n' ' ')"

block() { echo "HARDLINE BLOCK: $1" >&2; exit 1; }
scan()  { printf '%s\n' "$CMD" | grep -Eq "$1"; }

# 1. Pipe into any shell/interpreter (incl. busybox/ksh/fish/source)
scan '\|[[:space:]]*((ba|da|z|k)?sh|busybox[[:space:]]+(ba|da|z|k)?sh|fish|source)([[:space:]]|$)|\|[[:space:]]*(python[0-9.]*|node|ruby|perl)([[:space:]]|$)' \
  && block "pipe-to-shell/interpreter"

# 2. Command substitution / backticks wrapping a network fetch
scan '\$\((curl|wget)[^)]*\)|`[^`]*(curl|wget)[^`]*`' \
  && block "command-substitution of remote fetch"

# 3. Decode feeding an execution context
scan '(base64|xz|openssl)[[:space:]]+(-d|-D|--decode|--uncompress)[^;|]*\|' \
  && block "decode-to-pipeline (possible payload staging)"

# 4. eval/exec at command position (start, after ; & | or subshell open)
scan '(^|[;&|(])[[:space:]]*(eval|exec)[[:space:]]' \
  && block "eval/exec present"

# 5. Recursive rm with dangerous targets: absolute /, ~, $VAR, ${VAR}, ., ..
scan '(^|[[:space:];&|(])rm([[:space:]]+-{1,2}[A-Za-z-]+)+[[:space:]]+"?(/|~|\$HOME|\$\{?[A-Za-z_][A-Za-z0-9_]*\}?|\.\.?/?([[:space:]]|$))' \
  && block "recursive-delete of root/home/parent"
scan '(^|[[:space:];&|(])rm[^;&|]*--no-preserve-root' \
  && block "rm --no-preserve-root"

# 6. Privilege escalation ANYWHERE on the line
scan '(^|[;&|(/[:space:]])((sudo|doas|pkexec|runuser)([[:space:]]|$)|su[[:space:]]+(-c|-C|-l|-|root)([[:space:]]|$))' \
  && block "privilege escalation (sudo/doas/pkexec/runuser/su)"

# 7. Power, runlevel, fs/device tools ANYWHERE; dd with if= or of=
scan '(^|[;&|/[:space:]])((shutdown|reboot|poweroff|halt|telinit|mkfs[a-z0-9.]*|fdisk|parted)([[:space:]]|$)|init[[:space:]]+[06]([[:space:]]|$)|dd[[:space:]]+(if|of)=)' \
  && block "system power / filesystem / raw-device operation"

# 8. find on dangerous roots with -delete / -exec|-ok of dangerous cmds
scan 'find[[:space:]]+(/|/boot|/etc|/home|/root|/usr|/var|~|\$HOME|\$\{?[A-Za-z_][A-Za-z0-9_]*\}?)([[:space:]]|$)[^;&|]*(-delete|-exec[[:space:]]+(rm|sudo|dd|mkfs|sh)|-ok[[:space:]]+(rm|sudo))' \
  && block "find -delete/-exec against system tree"

# 9. xargs as an execution wrapper for dangerous commands
scan 'xargs[[:space:]]+(-[A-Za-z0-9]+[[:space:]]+)*(sudo|rm|dd|mkfs|sh|bash|shred|chmod|chown)([[:space:]]|$)' \
  && block "xargs executing dangerous command"

# 10. Deferred execution at command position
scan '(^|[;&|(])[[:space:]]*(at|batch|systemd-run)([[:space:]]|$)' \
  && block "deferred execution (at/batch/systemd-run)"

# 11. Fetch-to-file then execute/chmod (download-then-run)
scan '(curl|wget)[^;&|]*[[:space:]](-o|-O|--output|--output-document)[[:space:]]*[^;&|]+[[:space:]]*(&&|\|\||;)[[:space:]]*((ba|da|z|k)?sh|bash|source|\.|chmod)([[:space:]]|$)' \
  && block "download-then-execute sequence"

# 12. Force-push / mirror / ref deletion (parity with deny list rule 4; H-1)
scan 'git[[:space:]]+push[[:space:]]+(-f|--force[a-z-]*|--mirror|--delete)([[:space:]]|$)' \
  && block "force-push / mirror / ref deletion"

exit 0
