#!/usr/bin/env bash
# hardline-check.sh — defense-in-depth command scanner (R4 rewrite + R-15 audit hardening).
# Usage: hardline-check.sh '<candidate command line>'   (or unquoted args)
# Exit 0 = ALLOW. Exit 1 = BLOCK. Fail-closed: the hardline-gate plugin invokes
# this deterministically on every terminal command; if this script cannot run,
# the gate blocks. (smart_policy rule 9 also references it for the LLM layer.)
set -Eeuo pipefail
IFS=$'\n\t'

# Join all args (fixes truncation when the caller forgets quoting), flatten
# newlines/tabs/CR to spaces, and collapse runs of whitespace so cross-line
# pipes/chains are still scanned and token adjacency is stable.
CMD="${*:?usage: hardline-check.sh '<command>'}"
CMD="$(printf '%s\n' "$CMD" | tr '\n\r\t' ' ' | sed -E 's/[[:space:]]+/ /g')"

block() { echo "HARDLINE BLOCK: $1" >&2; exit 1; }
scan()  { printf '%s\n' "$CMD" | grep -Eq "$1"; }

# Q = a single or double quote character (used by quote-tolerant rules).
Q='["'"'"']'

# 1. Pipe / process substitution into any shell/interpreter
#    (incl. absolute paths, busybox, ksh, fish, source; python/node/ruby/perl)
scan '\|[[:space:]]*((/usr(/local)?/bin/)?(ba|da|z|k)?sh|busybox|fish|source|python[0-9.]*|node|ruby|perl)' \
  && block "pipe-to-shell/interpreter"
scan '((/usr(/local)?/bin/)?(ba|da|z|k)?sh|python[0-9.]*|node|perl|ruby)[[:space:]]*<\([^)]*\)' \
  && block "process substitution feeding interpreter"

# 2. Command substitution / backticks wrapping a network fetch
scan '\$\\((curl|wget)[^)]*\\)|`[^`]*(curl|wget)[^`]*`' \
  && block "command-substitution of remote fetch"

# 3. Decode feeding an execution context
scan '(base64|xz|openssl)[[:space:]]+(-d|-D|--decode|--uncompress)[^;|]*\|' \
  && block "decode-to-pipeline (possible payload staging)"

# 4. eval/exec at command position (start, after ; & | or subshell open), and
#    quote-obfuscated system verbs at command position ('sudo' id, "rm" -rf /)
scan '(^|[;&|(])[[:space:]]*(eval|exec)[[:space:]]' \
  && block "eval/exec present"
scan "(^|[;&|(][[:space:]]*)$Q(sudo|rm|dd|mkfs|shutdown|reboot|poweroff)$Q" \
  && block "quote-obfuscated system verb at command position"

# 5. Interpreter inline execution (-c / -e) via direct, absolute, or busybox
#    paths (usr-merged Ubuntu: /usr/bin/bash is the real binary; also versioned
#    binaries python3.14, node22). Quote-tolerant trailing boundary.
scan '(^|[;&|(/[:space:]])((/usr(/local)?/bin/|/bin/)?(ba|da|z|k)?sh|python[0-9.]*|node[0-9]*|ruby|perl)[[:space:]]+(-[a-zA-Z]*[ce][a-zA-Z]*)([[:space:]]|$|["'"'"'])' \
  && block "inline interpreter execution (-c / -e)"
scan 'busybox[[:space:]]+((ba|da|z|k)?sh|ash)[[:space:]]+(-[a-zA-Z]*[ce][a-zA-Z]*)([[:space:]]|$|["'"'"'])' \
  && block "busybox sh -c invocation"

# 5b. Recursive rm with dangerous targets: absolute /, ~, $VAR, ${VAR}, ., ..
scan '(^|[[:space:];&|(])rm([[:space:]]+-{1,2}[A-Za-z-]+)+[[:space:]]+"?(/|~|\$HOME|\$\{?[A-Za-z_][A-Za-z0-9_]*\}?|\.\.?/?([[:space:]]|$))' \
  && block "recursive-delete of root/home/parent"
scan '(^|[[:space:];&|(])rm[^;&|]*--no-preserve-root' \
  && block "rm --no-preserve-root"

# 6. Privilege escalation ANYWHERE on the line (backslash-tolerant)
scan '(^|[;&|(/[:space:]])[[:space:]]*\\?((sudo|doas|pkexec|runuser)([[:space:]]|$)|su[[:space:]]+(-c|-C|-l|-|root)([[:space:]]|$))' \
  && block "privilege escalation (sudo/doas/pkexec/runuser/su)"

# 7. Power, runlevel, fs/device tools ANYWHERE; dd with if= or of=
scan '(^|[;&|/[:space:]])((shutdown|reboot|poweroff|halt|telinit|mkfs[a-z0-9.]*|fdisk|parted)([[:space:]]|$)|init[[:space:]]+[06]([[:space:]]|$)|dd[[:space:]]+(if|of)=)' \
  && block "system power / filesystem / raw-device operation"

# 8. find on dangerous roots with -delete / -exec|-ok of dangerous cmds
scan 'find[[:space:]]+(/|/boot|/etc|/home|/root|/usr|/var|~|\$HOME|\$\{?[A-Za-z_][A-Za-z0-9_]*\}?)([[:space:]]|$)[^;&|]*(-delete|-exec[[:space:]]+(rm|sudo|dd|mkfs|sh|bash|zsh|dash)|-ok[[:space:]]+(rm|sudo))' \
  && block "find -delete/-exec against system tree"

# 8b. find -exec <shell|interpreter> -c on ANY root (payload may contain
#     anything; R-14 + C-2: include python family)
scan 'find[[:space:]]+[^;&|]*-exec[[:space:]]+((/usr(/local)?/bin/|/bin/)?(sh|bash|zsh|dash|python[0-9.]*))[[:space:]]+-[a-zA-Z]*c' \
  && block "find -exec shell/interpreter -c invocation"

# 9. xargs as an execution wrapper for dangerous commands
scan 'xargs[[:space:]]+(-[A-Za-z0-9]+[[:space:]]+)*(sudo|rm|dd|mkfs|sh|bash|shred|chmod|chown)([[:space:]]|$)' \
  && block "xargs executing dangerous command"

# 10. Deferred execution at command position
scan '(^|[;&|(])[[:space:]]*(at|batch|systemd-run)([[:space:]]|$)' \
  && block "deferred execution (at/batch/systemd-run)"

# 11. Download-then-execute / install: any fetch (curl/wget) followed — possibly
#     through intervening ; && || segments — by a shell/interpreter/install verb.
#     Closes H-4: python3/node payloads, crontab persistence, sleep-gap chains.
scan '(curl|wget)[^;&|]*([;&|][[:space:]]*[^;&|]*)*[[:space:]]*((/usr(/local)?/bin/)?(ba|da|z|k)?sh|bash|python[0-9.]*|node|ruby|perl|crontab|at|install|chmod)([[:space:]]|$)' \
  && block "download-then-execute / install sequence"
scan 'git[[:space:]]+clone[^;&|]*([;&|][[:space:]]*[^;&|]*)*[[:space:]]*((/usr(/local)?/bin/)?(ba|da|z|k)?sh|bash|python[0-9.]*|node|make|sudo)([[:space:]]|$)' \
  && block "git-clone-then-execute sequence"

# 12. Force-push / mirror / ref deletion (parity with deny list rule 4; H-1)
scan 'git[[:space:]]+push[[:space:]]+(-f|--force[a-z-]*|--mirror|--delete)([[:space:]]|$)' \
  && block "force-push / mirror / ref deletion"

# 13. Container escape: docker run/create/exec bind-mounting host paths into a
#     container (verified vector: -v /:/host reads the whole host). Covers
#     whitespace and '=' separators and the --mount source= form. Named volumes
#     (source does not start with /, ~, $, ..) and docker ps/logs remain allowed.
scan 'docker[[:space:]]+(run|create|exec)[^;&|]*(-v|--volume)([[:space:]]|=)(")?(/|~|\$HOME|\$\{?[A-Za-z_][A-Za-z0-9_]*\}?|\.\.)' \
  && block "docker bind-mount of host path"
scan 'docker[[:space:]]+(run|create|exec)[^;&|]*--mount[^;&|]*source=(")?(/|~|\$HOME|\$\{?[A-Za-z_][A-Za-z0-9_]*\}?|\.\.)' \
  && block "docker --mount bind of host path"

# 13b. Docker privilege-escalation flags and compose-file host mounts (H-5).
#      --security-opt with ANY value is gated (seccomp=unconfined is the
#      headline risk; run-sandbox.sh uses it internally but is invoked as
#      `bash scripts/run-sandbox.sh`, which this scanner never sees).
scan 'docker[[:space:]]+(run|create)[^;&|]*(--privileged|--cap-add|--security-opt|--pid[[:space:]]*=?[[:space:]]*host|--network[[:space:]]*=?[[:space:]]*host|--net[[:space:]]*=?[[:space:]]*host)' \
  && block "docker container privilege escalation options"
scan 'docker[[:space:]]+compose[^;&|]*(-f|--file)' \
  && block "docker compose with custom file (human review required)"
scan 'docker[[:space:]]+cp[^;&|]+[[:space:]]+(/etc/|/boot/|/root|/usr/|/bin/|/sbin/|/var/|/mnt/|/media/|/opt/|/srv/)' \
  && block "docker cp writing to protected host path"

# 14. Service lifecycle control (M-4): systemctl stop/disable/restart/start/kill
#     and the legacy `service <unit> stop` wrapper.
scan '(^|[;&|/[:space:]])(systemctl[[:space:]]+(stop|disable|restart|start|kill)[[:space:]]+|service[[:space:]]+[a-zA-Z0-9_.-]+[[:space:]]+(stop|disable|restart|start|kill)([[:space:]]|$))' \
  && block "service lifecycle operation"

exit 0
