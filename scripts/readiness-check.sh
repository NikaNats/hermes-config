#!/usr/bin/env bash
# Production Readiness Check (spec 7). Read-only machine audit.
# Usage: bash scripts/readiness-check.sh
# Prints PASS/FAIL/INFO per item; exits 0 when no FAIL, 1 when any FAIL.
set -Eeuo pipefail
IFS=$'\n\t'

trap 'echo "Command failed at line $LINENO" >&2' ERR

REPO="$HOME/src/hermes-config"
HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
CFG="$HERMES_HOME/config.yaml"
PASS=0; FAIL=0; INFO=0

ok()   { echo "PASS  $1"; PASS=$((PASS+1)); }
bad()  { echo "FAIL  $1"; FAIL=$((FAIL+1)); }
note() { echo "INFO  $1"; INFO=$((INFO+1)); }
sec()  { echo; echo "== $1 =="; }
has()  { command -v "$1" >/dev/null 2>&1; }

# ---------------------------------------------------------------- WSL
sec "WSL Environment"
uname -r | grep -qi microsoft && ok "WSL2 kernel active ($(uname -r))" || bad "WSL2 kernel active"

APT_SIM=$(timeout 90 apt-get -s upgrade 2>/dev/null) || true
PENDING=$(printf '%s\n' "$APT_SIM" | grep -c '^Inst' || true)
if [ -z "$APT_SIM" ]; then
  note "distro updated (apt simulate unavailable)"
elif [ "$PENDING" = "0" ]; then
  ok "distro updated (0 pending upgrades)"
else
  bad "distro updated ($PENDING pending upgrades)"
fi

[ "$(ps -p 1 -o comm= 2>/dev/null)" = "systemd" ] && ok "systemd enabled" || bad "systemd enabled"
[ "$(id -u)" -ne 0 ] && ok "default user non-root (uid $(id -u))" || bad "default user non-root"

WSLCFG=""
for f in /mnt/c/Users/*/.wslconfig; do [ -f "$f" ] && WSLCFG="$f"; done
if [ -n "$WSLCFG" ] && grep -qE '^\s*(memory|processors)\s*=' "$WSLCFG"; then
  ok ".wslconfig limits set ($WSLCFG)"
elif [ -n "$WSLCFG" ]; then
  bad ".wslconfig exists but no memory/processors limits ($WSLCFG)"
else
  bad ".wslconfig memory/CPU limits set (not found under /mnt/c/Users/*/)"
fi

grep -q 'appendWindowsPath\s*=\s*false' /etc/wsl.conf 2>/dev/null \
  && ok "Windows PATH injection disabled (appendWindowsPath=false)" \
  || bad "Windows PATH injection disabled (appendWindowsPath=false not in /etc/wsl.conf)"

case "$(readlink -f "$HOME/src")" in
  /mnt/*) bad "source code on Linux filesystem (~/src is on /mnt)" ;;
  *)      ok "source code on Linux filesystem (~/src)" ;;
esac

# ---------------------------------------------------- Hermes config
sec "Hermes Configuration"
git -C "$REPO" ls-files 2>/dev/null | grep -q '^SOUL.md$' \
  && ok "config artifacts versioned (repo: $REPO)" || bad "config artifacts versioned"
git -C "$REPO" ls-files 2>/dev/null | grep -q '^prompts/' \
  && ok "prompts modular & versioned (prompts/)" || bad "prompts modular & versioned"
note "deterministic settings: temperature is model/provider-level (documented gap, spec 6.1)"

[ "$(hermes config get approvals.mode 2>/dev/null)" = "smart" ] \
  && ok "approvals.mode=smart (explicit tool permissions)" || bad "approvals.mode=smart"

DCNT=$(CFG_PATH="$CFG" python3 -c "
import os
try:
    import yaml
    cfg = yaml.safe_load(open(os.environ['CFG_PATH']))
    deny = (cfg.get('approvals') or {}).get('deny') or []
    print(len(deny))
except ImportError:
    # Fallback: lightweight regex (original behavior), tolerant of indentation.
    import re
    t = open(os.environ['CFG_PATH']).read()
    m = re.search(r'deny:\n((?:[ \t]+- .*\n)+)', t)
    print(len(m.group(1).strip().splitlines()) if m else 0)" 2>/dev/null || echo 0)
[ "$DCNT" -ge 27 ] && ok "destructive commands blocked (deny list: $DCNT patterns)" \
  || bad "destructive commands blocked (deny list: $DCNT patterns)"

note "filesystem ACLs: not natively supported (OS perms + .agentignore instead)"
[ -f "$HOME/.agentignore" ] && [ -f "$REPO/.gitignore" ] \
  && ok "secret dirs excluded (.agentignore + .gitignore)" || bad "secret dirs excluded"
[ "$(hermes config get security.redact_secrets 2>/dev/null)" = "true" ] \
  && ok "secret redaction enabled" || bad "secret redaction enabled"
[ -d "$HERMES_HOME/logs" ] && ok "logs/audit present ($HERMES_HOME/logs)" \
  || bad "logs/audit present"

# ------------------------------------------------- Agent tooling
sec "Agent Tooling (RTK / LCM)"
if [ -d "$HERMES_HOME/plugins/rtk-rewrite" ]; then
  ok "RTK plugin installed ($HERMES_HOME/plugins/rtk-rewrite)"
else
  note "RTK plugin not installed (optional: rtk init --agent hermes)"
fi
grep -q 'rtk-rewrite' "$CFG" && ok "RTK enabled (plugins.enabled: rtk-rewrite)" \
  || note "rtk-rewrite not in plugins.enabled (optional)"
if has rtk; then
  ok "rtk binary on PATH ($(rtk --version 2>/dev/null | head -1))"
else
  note "rtk not on PATH (optional: brew install rtk / install.sh)"
fi
if [ -d "$HERMES_HOME/plugins/hermes-lcm" ]; then
  ok "hermes-lcm plugin installed"
else
  note "hermes-lcm plugin not installed (optional)"
fi
grep -qE '^[[:space:]]*engine:[[:space:]]*lcm[[:space:]]*$' "$CFG" && ok "context engine = lcm (hermes-lcm active)" \
  || note "context.engine=lcm not set (hermes-lcm not active)"
[ -f "$HERMES_HOME/lcm.db" ] && ok "lcm.db present" \
  || note "lcm.db not present (hermes-lcm not active)"

# ------------------------------------------------- Coding workflow
sec "Coding Workflow"
[ -n "$(git config --global user.name 2>/dev/null)" ] && [ -n "$(git config --global user.email 2>/dev/null)" ] \
  && ok "git identity configured (global: $(git config --global user.name) <$(git config --global user.email)>)" \
  || bad "git identity configured"
[ -f "$REPO/references/cicd-guardrails.md" ] \
  && ok "branching strategy defined (cicd-guardrails.md)" || bad "branching strategy defined"

if gpg --list-secret-keys 2>/dev/null | grep -q '^sec'; then
  ok "commit signing key present"
else
  note "commit signing: no GPG key (documented decision; commit.gpgsign off)"
fi

LINT=""
for t in node npm uv; do has "$t" || LINT="$LINT $t"; done
[ -z "$LINT" ] && ok "linters/formatters runtimes present (node, npm, uv)" \
  || note "linters/formatters missing:$LINT (cargo/go also absent)"
note "test runner: per-project (no global runner; use project tooling)"

grep -q 'validation commands' "$REPO/SOUL.md" && ok "validation required by SOUL.md (reproducible validation commands)" \
  || bad "validation required by SOUL.md"
grep -qi 'branch' "$REPO/references/cicd-guardrails.md" \
  && ok "branch/worktree policy defined (cicd-guardrails.md)" || bad "branch/worktree policy defined"
[ -f "$REPO/references/backup-recovery.md" ] \
  && ok "backup/snapshot procedure defined (backup-recovery.md)" || bad "backup/snapshot procedure defined"

# ---------------------------------------------------------- Safety
sec "Safety"
if sudo -n true 2>/dev/null; then
  bad "no unrestricted sudo (passwordless sudo WORKS)"
else
  ok "no unrestricted sudo (passwordless sudo not available)"
fi
grep -qE '^[[:space:]]+- sudo \*' "$CFG" && ok "sudo denied to agent (deny: 'sudo *')" || bad "sudo denied to agent (deny: 'sudo *')"
grep -q 'rm -rf /' "$CFG" && grep -q 'rm -rf ~' "$CFG" && ok "no broad rm -rf (deny list)" \
  || bad "no broad rm -rf (deny list)"
grep -q 'git push --force' "$CFG" && ok "no force-push (deny list)" || bad "no force-push (deny list)"
grep -q 'Never expose secrets' "$REPO/SOUL.md" && ok "no secret access (SOUL.md rule 7)" \
  || bad "no secret access (SOUL.md rule 7)"
grep -q 'untrusted' "$REPO/SOUL.md" && ok "external content treated as untrusted (SOUL.md rule 8)" \
  || bad "external content treated as untrusted"
[ -f "$REPO/references/prompt-injection-defense.md" ] \
  && ok "prompt-injection defenses documented" || bad "prompt-injection defenses documented"

DOCKER_OK=$(has docker && echo yes || echo no)
DF_OK=$([ -f "$REPO/sandbox/Dockerfile" ] && echo yes || echo no)
RS_OK=$([ -f "$REPO/scripts/run-sandbox.sh" ] && echo yes || echo no)
[ "$DOCKER_OK" = "yes" ] && [ "$DF_OK" = "yes" ] && [ "$RS_OK" = "yes" ] \
  && ok "sandbox available (docker + sandbox/Dockerfile + run-sandbox.sh)" \
  || bad "sandbox available (docker: $DOCKER_OK, Dockerfile: $DF_OK, run-sandbox.sh: $RS_OK)"

BACKUP_FOUND=""
for f in "$HOME"/ubuntu-backup-*.tar /mnt/c/Users/*/ubuntu-backup-*.tar; do
  [ -f "$f" ] && BACKUP_FOUND="$f"
done
[ -n "$BACKUP_FOUND" ] && ok "WSL export backup exists ($BACKUP_FOUND)" \
  || bad "WSL export backup exists (none found — run in PowerShell: wsl --export Ubuntu ubuntu-backup-<date>.tar)"

# ---------------------------------------------------- Non-coding use
sec "Non-Coding Use"
DOC_MISSING=""
for t in pandoc pdftotext soffice; do has "$t" || DOC_MISSING="$DOC_MISSING $t"; done
[ -z "$DOC_MISSING" ] && ok "document parsing tools installed (pandoc, poppler, soffice)" \
  || note "document parsing tools missing:$DOC_MISSING (user install: sudo apt install -y pandoc poppler-utils ...)"

LOG_MISSING=""
for t in lnav duckdb; do has "$t" || LOG_MISSING="$LOG_MISSING $t"; done
[ -z "$LOG_MISSING" ] && ok "log analysis tools installed (lnav, duckdb)" \
  || note "log analysis tools missing:$LOG_MISSING (user install)"

[ -d "$HOME/agent/reports" ] && ok "report output dir defined (~/agent/reports)" \
  || note "report output dir: ~/agent/reports (created on first report)"
[ -f "$REPO/references/research-workflow.md" ] \
  && ok "research mode: citation + uncertainty (research-workflow.md)" || bad "research mode: citation + uncertainty"
[ -f "$REPO/references/sysadmin-readonly.md" ] \
  && ok "sysadmin mode: read-only diagnostics (sysadmin-readonly.md)" || bad "sysadmin mode: read-only diagnostics"

echo
echo "----------------------------------------"
echo "readiness: $PASS pass, $FAIL fail, $INFO info"
if [ "$FAIL" -eq 0 ]; then exit 0; else exit 1; fi
