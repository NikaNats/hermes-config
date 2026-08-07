#!/usr/bin/env bash
# Production Readiness Check (spec 7). Read-only machine audit.
# Usage: bash scripts/readiness-check.sh
# Prints PASS/FAIL/INFO per item; exits 0 when no FAIL, 1 when any FAIL.
set -Eeuo pipefail
IFS=$'\n\t'

trap 'echo "Command failed at line $LINENO" >&2' ERR

REPO="$HOME/src/hermes-config"
# Hermes' canonical default home is ~/.hermes (hermes_constants.py
# _get_platform_default_hermes_home); HERMES_HOME overrides it when set.
HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
CFG="$HERMES_HOME/config.yaml"
# R-16: print the resolved home and refuse to audit a nonexistent one — under
# cron/systemd/CI the profile export may be absent, and the fallback would
# silently audit the wrong path.
echo "INFO: using HERMES_HOME=$HERMES_HOME" >&2
[ -d "$HERMES_HOME" ] || {
    echo "FATAL: HERMES_HOME does not exist ($HERMES_HOME); refusing to audit the wrong path." >&2
    echo "       Set HERMES_HOME (e.g. export HERMES_HOME=\$HOME/.config/hermes) or run 'hermes setup'." >&2
    exit 1
}
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
  # R-01: apt drift is environmental (OS package state), not a config defect —
  # reclassified from FAIL so the exit-0-iff-FAIL=0 contract is truthful.
  note "distro drift ($PENDING pending upgrades — run: sudo apt upgrade)"
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
[ -L "$REPO/prompts/base.md" ] && [ -e "$REPO/prompts/base.md" ] \
  && ok "prompts/base.md symlink resolves" || bad "prompts/base.md symlink resolves (dangling or missing)"
# R-07: verify the LIVE wiring, not just repo content — if these symlinks
# break, the agent runs without its safety charter while the audit would
# otherwise still report green.
[ -L "$HERMES_HOME/SOUL.md" ] \
  && [ "$(readlink -f "$HERMES_HOME/SOUL.md")" = "$(readlink -f "$REPO/SOUL.md")" ] \
  && ok "SOUL.md symlink live -> repo" || bad "SOUL.md symlink live -> repo"
# R-24: symlink resolution is NOT enough. Hermes scans SOUL.md for prompt
# injection (incl. hidden HTML comments) and blocks the WHOLE file when one
# matches -> silent fallback to the built-in default identity, safety charter
# lost while the disk audit still looks green. Verify liveness + scanner-safety.
SOUL_LIVE="$(readlink -f "$HERMES_HOME/SOUL.md" 2>/dev/null)"
if [ -s "$SOUL_LIVE" ] && ! grep -q -- '<!--' "$SOUL_LIVE"; then
  ok "SOUL.md live, non-empty, scanner-safe (no HTML comments)"
else
  bad "SOUL.md live, non-empty, scanner-safe (empty or contains HTML comments)"
fi
[ -L "$HERMES_HOME/prompts" ] \
  && [ "$(readlink -f "$HERMES_HOME/prompts")" = "$(readlink -f "$REPO/prompts")" ] \
  && ok "prompts/ symlink live -> repo" || bad "prompts/ symlink live -> repo"
note "deterministic settings: temperature is model/provider-level (documented gap, spec 6.1)"

[ "$(hermes config get approvals.mode 2>/dev/null)" = "smart" ] \
  && ok "approvals.mode=smart (explicit tool permissions)" || bad "approvals.mode=smart"
[ "$(hermes config get approvals.cron_mode 2>/dev/null)" = "deny" ] \
  && ok "approvals.cron_mode=deny (scheduled jobs blocked)" || bad "approvals.cron_mode=deny"
[ "$(hermes config get security.tirith_enabled 2>/dev/null)" = "true" ] \
  && ok "tirith threat-scanner enabled" || bad "tirith threat-scanner enabled"

DCNT=$(CFG_PATH="$CFG" python3 -c "
import os, sys

path = os.environ.get('CFG_PATH', '')
if not path or not os.path.isfile(path):
    print(0)
    sys.exit(0)

try:
    import yaml
    with open(path) as fh:
        cfg = yaml.safe_load(fh)
    if not isinstance(cfg, dict):
        print(0)
        sys.exit(0)
    deny = (cfg.get('approvals') or {}).get('deny') or []
    print(len(deny) if isinstance(deny, list) else 0)
except ImportError:
    # Fallback: lightweight regex (no PyYAML available), tolerant of indentation.
    import re
    try:
        t = open(path).read()
    except Exception:
        print(0)
        sys.exit(0)
    m = re.search(r'deny:\s*\[([^\]]+)\]', t)
    if m:
        print(len([x for x in m.group(1).split(',') if x.strip()]))
    else:
        m = re.search(r'deny:\n((?:[ \t]+- .*\n?)+)', t)
        print(len(m.group(1).strip().splitlines()) if m else 0)
except Exception:
    # Catch-all: yaml.YAMLError, PermissionError, etc. -> no false PASS
    print(0)
" 2>/dev/null || echo 0)
[ "$DCNT" -ge 137 ] && ok "destructive commands blocked (deny list: $DCNT patterns)" \
  || bad "destructive commands blocked (deny list: $DCNT patterns, expected >= 137)"

note "filesystem ACLs: not natively supported (OS perms + .agentignore instead)"
[ -f "$HOME/.agentignore" ] && [ -f "$REPO/.gitignore" ] \
  && ok "secret dirs excluded (.agentignore + .gitignore)" || bad "secret dirs excluded"
# R-10: existence is not enough — an empty .agentignore defeats its purpose.
# Array form: immune to the script-level IFS=$'\n\t' (word splitting on spaces).
AGENTIGNORE_MIN=(.env '.env.*' '*.pem' '*.key' id_rsa .ssh/ .aws/ .gnupg/)
MISSING=""
for pat in "${AGENTIGNORE_MIN[@]}"; do
    grep -qxF "$pat" "$HOME/.agentignore" 2>/dev/null || MISSING="$MISSING $pat"
done
[ -z "$MISSING" ] && ok ".agentignore contains secret patterns" \
  || bad ".agentignore missing patterns:$MISSING"
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
RTK_ON=$(CFG_PATH="$CFG" python3 -c "
import os, yaml
try:
    cfg = yaml.safe_load(open(os.environ['CFG_PATH'])) or {}
    en = ((cfg.get('plugins') or {}).get('enabled')) or []
    print('yes' if isinstance(en, list) and 'rtk-rewrite' in en else 'no')
except Exception:
    print('no')
" 2>/dev/null || echo no)
[ "$RTK_ON" = "yes" ] && ok "RTK enabled (plugins.enabled contains rtk-rewrite)" \
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
# R-15 (C-1): deterministic hardline gate must be installed AND enabled — the
# scanner is only deterministic when every terminal command passes through it.
if [ -d "$HERMES_HOME/plugins/hardline-gate" ]; then
  ok "hardline-gate plugin installed ($HERMES_HOME/plugins/hardline-gate)"
else
  bad "hardline-gate plugin installed (install: mkdir -p \$HERMES_HOME/plugins/hardline-gate && cp -r plugins/hardline-gate/. \$HERMES_HOME/plugins/hardline-gate/)"
fi
HG_ON=$(CFG_PATH="$CFG" python3 -c "
import os, yaml
try:
    cfg = yaml.safe_load(open(os.environ['CFG_PATH'])) or {}
    en = ((cfg.get('plugins') or {}).get('enabled')) or []
    print('yes' if isinstance(en, list) and 'hardline-gate' in en else 'no')
except Exception:
    print('no')
" 2>/dev/null || echo no)
[ "$HG_ON" = "yes" ] && ok "hardline-gate enabled (plugins.enabled contains hardline-gate)" \
  || bad "hardline-gate enabled (plugins.enabled missing hardline-gate — deterministic gate inactive)"

# ── LCM redaction gate ──────────────────────────────────────────────
if grep -qE '^[[:space:]]*engine:[[:space:]]*lcm[[:space:]]*$' "$CFG" 2>/dev/null; then
    # LCM is active — redaction MUST be enabled
    if grep -Eq '^[[:space:]]*LCM_SENSITIVE_PATTERNS_ENABLED=true([[:space:]]|$)' "$HERMES_HOME/.env" 2>/dev/null; then
        ok "LCM secret redaction enabled (LCM_SENSITIVE_PATTERNS_ENABLED=true)"
    else
        bad "LCM active but LCM_SENSITIVE_PATTERNS_ENABLED not set to true in $HERMES_HOME/.env"
    fi
else
    note "LCM not active — redaction check skipped"
fi
# ─────────────────────────────────────────────────────────────────────

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

grep -q 'validation commands' "$REPO/SOUL.md" \
  && ok "validation required by SOUL.md (principle 10)" \
  || bad "validation required by SOUL.md (anchor 'validation commands' missing)"
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
# R-08: one authoritative structural YAML assertion instead of fragile greps
# that false-positive on smart_policy prose and false-negative on flow style.
SAFETY=$(CFG_PATH="$CFG" python3 -c "
import os, yaml, sys
p = os.environ.get('CFG_PATH', '')
try:
    deny = (yaml.safe_load(open(p)).get('approvals') or {}).get('deny') or []
    deny = set(deny) if isinstance(deny, list) else set()
except Exception:
    print('missing'); sys.exit(0)
need = {'sudo *', 'rm -rf /', 'rm -rf ~', 'git push --force*', 'git push -f*',
        '/usr/bin/sudo *', 'env sudo *', 'rm -rf --no-preserve-root*',
        'rm --recursive*', 'poweroff*', 'doas *', 'pkexec *', 'git push --mirror*',
        'docker run * -v /*', 'docker run * --mount type=bind*',
        'docker create * --volume /*'}
print('ok' if need.issubset(deny) else 'missing:' + ','.join(sorted(need - deny)))
" 2>/dev/null || echo missing)
case "$SAFETY" in
  ok) ok "critical deny patterns present (structural YAML check)" ;;
  *)  bad "critical deny patterns present ($SAFETY)" ;;
esac
# R-24: SOUL.md guarantees are audited against natural prose anchors from
# references/soul-safety-manifest.yaml (audit-only sidecar — never prompt-
# loaded). HTML markers were retracted: they tripped Hermes' injection scanner
# and silently dropped the whole safety charter.
MISSING_ANCHORS=""
if [ -f "$REPO/references/soul-safety-manifest.yaml" ]; then
  while IFS= read -r anchor; do
    [ -n "$anchor" ] || continue
    grep -qF -- "$anchor" "$REPO/SOUL.md" || MISSING_ANCHORS="$MISSING_ANCHORS|$anchor"
  done < <(grep -oE 'anchor: *"[^"]+"' "$REPO/references/soul-safety-manifest.yaml" | cut -d'"' -f2)
  [ -z "$MISSING_ANCHORS" ] \
    && ok "SOUL.md safety guarantees present (all manifest anchors)" \
    || bad "SOUL.md safety guarantees present (missing:$MISSING_ANCHORS)"
else
  bad "SOUL.md safety guarantees present (references/soul-safety-manifest.yaml missing)"
fi
[ -f "$REPO/references/prompt-injection-defense.md" ] \
  && ok "prompt-injection defenses documented" || bad "prompt-injection defenses documented"
[ -f "$REPO/scripts/hardline-check.sh" ] && [ -x "$REPO/scripts/hardline-check.sh" ] \
  && ok "hardline command scanner present (scripts/hardline-check.sh)" \
  || bad "hardline command scanner present (scripts/hardline-check.sh missing or not executable)"
# R-17: model-credential file must be owner-only (600/400)
ENV_FILE="$HERMES_HOME/.env"
if [ -f "$ENV_FILE" ]; then
  PERMS=$(stat -c '%a' "$ENV_FILE")
  case "$PERMS" in
    600|400) ok ".env permissions ($PERMS)" ;;
    *)       bad ".env permissions ($PERMS — must be 600/400)" ;;
  esac
else
  note ".env not present (model creds not configured)"
fi

DOCKER_OK=$(has docker && echo yes || echo no)
DF_OK=$([ -f "$REPO/sandbox/Dockerfile" ] && echo yes || echo no)
RS_OK=$([ -f "$REPO/scripts/run-sandbox.sh" ] && echo yes || echo no)
[ "$DOCKER_OK" = "yes" ] && [ "$DF_OK" = "yes" ] && [ "$RS_OK" = "yes" ] \
  && ok "sandbox available (docker + sandbox/Dockerfile + run-sandbox.sh)" \
  || bad "sandbox available (docker: $DOCKER_OK, Dockerfile: $DF_OK, run-sandbox.sh: $RS_OK)"
# R-09: liveness, not just binary presence
docker info >/dev/null 2>&1 && ok "docker daemon running" || bad "docker daemon running"
has bwrap && ok "bubblewrap installed" || bad "bubblewrap installed (sudo apt install bubblewrap)"
if bwrap --unshare-user --die-with-parent --ro-bind / / --proc /proc --dev /dev \
        --unshare-pid --unshare-uts --unshare-ipc --new-session --chdir / true 2>/dev/null; then
  ok "user namespaces available (bwrap --unshare-user)"
else
  bad "user namespaces available (check kernel.unprivileged_userns_clone)"
fi

# R-15 (H-3): Firecrawl must bind loopback, never 0.0.0.0 (recovery docs used to
# instruct PORT=3002 which re-exposes the scraping API on all interfaces).
FC_ENV="$HOME/src/firecrawl/.env"
if [ -f "$FC_ENV" ]; then
  if grep -Eq '^PORT=127\.0\.0\.1:3002([[:space:]]|$)' "$FC_ENV"; then
    ok "Firecrawl loopback binding (PORT=127.0.0.1:3002 in $FC_ENV)"
  else
    bad "Firecrawl loopback binding (PORT is not 127.0.0.1:3002 in $FC_ENV — R-14 regression)"
  fi
else
  note "Firecrawl not deployed (~/src/firecrawl/.env absent) — binding check skipped"
fi
# M-8: local-mode SSRF exemption has no compensating guard. On non-WSL hosts
# adjacent to cloud/LAN services, TERMINAL_ENV=local is dangerous.
if [ -n "${TERMINAL_ENV:-}" ] && [ "$TERMINAL_ENV" != "local" ]; then
  ok "TERMINAL_ENV set to non-local (SSRF gate active in browser tool)"
elif [ -n "${TERMINAL_ENV:-}" ] && [ "$TERMINAL_ENV" = "local" ]; then
  note "TERMINAL_ENV=local — browser SSRF gate skipped by design (documented); verify host isolation"
else
  note "TERMINAL_ENV unset — default local mode skips browser SSRF gate; verify host isolation"
fi

BACKUP_FOUND=""
for f in "$HOME"/ubuntu-backup-*.tar /mnt/c/Users/*/ubuntu-backup-*.tar; do
  [ -s "$f" ] || continue                                          # zero-byte fails
  [ "$(dd if="$f" bs=1 skip=257 count=5 2>/dev/null)" = "ustar" ] || continue
  BACKUP_FOUND="$f"
done
if [ -n "$BACKUP_FOUND" ]; then
  ok "WSL export backup exists ($BACKUP_FOUND)"
  BD="$(basename "$BACKUP_FOUND" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | head -1 || true)"
  if [ -n "$BD" ]; then
    AGE=$(( ( $(date +%s) - $(date -d "$BD" +%s 2>/dev/null || date +%s) ) / 86400 ))
    if [ "$AGE" -le 30 ]; then ok "backup freshness (${AGE}d old)";
    else note "backup stale (${AGE}d — refresh: wsl --export Ubuntu <file>.tar)"; fi
  fi
else
  bad "WSL export backup exists (none valid/non-empty — run in PowerShell: wsl --export Ubuntu ubuntu-backup-<date>.tar)"
fi
# R4 (C-4, H-3, L-4): commit-time secret scan, git remote, repo .gitignore, corpus
# pre-commit's generated hook is a generic shim (hook-impl --config=...) — the
# gitleaks wiring lives in .pre-commit-config.yaml, so the check is structural:
# shim installed AND gitleaks configured.
if [ -f "$REPO/.git/hooks/pre-commit" ] && grep -q 'pre-commit' "$REPO/.git/hooks/pre-commit" 2>/dev/null \
   && grep -q 'gitleaks' "$REPO/.pre-commit-config.yaml" 2>/dev/null; then
  ok "commit-time secret scan wired (.git/hooks/pre-commit -> pre-commit -> gitleaks)"
else
  bad "commit-time secret scan wired (run: pipx install pre-commit && pre-commit install)"
fi

if git -C "$REPO" remote get-url origin >/dev/null 2>&1; then
  ok "git remote configured (repo recoverable off-box)"
else
  bad "git remote configured (none — 1-Click Recovery cannot clone; git remote add origin ... && git push -u origin main)"
fi

GITIGNORE_MIN=(.env '.env.*' '*.pem' '*.key' id_rsa)
GI_MISSING=""
for pat in "${GITIGNORE_MIN[@]}"; do
  grep -qxF "$pat" "$REPO/.gitignore" 2>/dev/null || GI_MISSING="$GI_MISSING $pat"
done
[ -z "$GI_MISSING" ] && ok "repo .gitignore contains secret patterns" \
  || bad "repo .gitignore missing patterns:$GI_MISSING"

if bash "$REPO/scripts/hardline-corpus-test.sh" >/dev/null 2>&1; then
  ok "hardline bypass corpus passes (scripts/hardline-corpus-test.sh)"
else
  bad "hardline bypass corpus passes (regression in scripts/hardline-check.sh)"
fi

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
