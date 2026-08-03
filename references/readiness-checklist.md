# Production Readiness Checklist (spec 7)

Statuses as of 2026-08-03, produced by the automated audit:

    bash ~/src/hermes-config/scripts/readiness-check.sh

Re-run that script any time before letting Hermes do real work — the doc
below is a snapshot, the script is the live check. Legend: OK = ready,
ACTION = needs you, NOTE = documented gap / per-project.

## WSL Environment

| Item | Status | Evidence / action |
|---|---|---|
| WSL2 active | OK | kernel 6.18.33.2-microsoft-standard-WSL2 |
| Distro updated | ACTION | 18 pending upgrades: sudo apt update && sudo apt upgrade |
| systemd enabled | OK | PID 1 = systemd |
| Default user non-root | OK | nika (uid 1000) |
| .wslconfig memory/CPU limits | ACTION | not found under /mnt/c/Users/*/; create .wslconfig: [wsl2] memory=..GB, processors=N, then wsl --shutdown |
| Windows PATH injection disabled | OK | /etc/wsl.conf appendWindowsPath=false |
| Source code on Linux fs | OK | ~/src on ext4 (not /mnt) |

## Hermes Configuration

| Item | Status | Evidence / action |
|---|---|---|
| Config in version control | OK | repo ~/src/hermes-config tracks SOUL.md, prompts/, references/, scripts/; live config.yaml machine-local by design |
| Prompts modular & versioned | OK | prompts/: 6 personas (coding/review/ops/research/automation/production) |
| Production profile deterministic | NOTE | temperature is model/provider-level; behavior block realized via prompts/production.md |
| Tool permissions explicitly configured | OK | approvals.mode=smart, cron_mode=deny |
| Destructive commands require confirmation | OK | approvals.deny: 27 patterns |
| Filesystem allow/deny lists | NOTE | not natively supported; closest: OS user perms, ~/agent layout, .agentignore, redact_secrets |
| Secret directories excluded | OK | ~/.agentignore + repo .gitignore + security.redact_secrets=true |
| Logs and audit trails enabled | OK | ~/.config/hermes/logs/ (agent.log, errors.log) + session store |

## Coding Workflow

| Item | Status | Evidence / action |
|---|---|---|
| Git identity configured | OK | global: NikaNats <nika.nacvlishvili1@gmail.com> |
| Branching strategy defined | OK | references/cicd-guardrails.md (branch-per-change, PR) |
| Commit signing configured | NOTE | no GPG key; commit.gpgsign off (documented decision) — optional: gpg --gen-key |
| Linters/formatters installed | OK | node/npm/uv present; cargo/go absent (add per project) |
| Test runner known | NOTE | per-project; no global runner |
| Validation commands required | OK | SOUL.md principle 10 (prefer tests/linting/validation) |
| Changes in branches/worktrees | OK | policy in cicd-guardrails.md + preflight-checklist.md |
| Backups before broad edits | OK | references/backup-recovery.md (wsl --export, git stash/branch pattern) |

## Safety

| Item | Status | Evidence / action |
|---|---|---|
| No unrestricted sudo | OK | passwordless sudo NOT available; deny 'sudo *' |
| No broad rm -rf | OK | deny 'rm -rf /', 'rm -rf ~'; trash.sh for deletes |
| No force-push by default | OK | deny 'git push --force*' |
| No secret access | OK | SOUL.md rule 7 + redact_secrets + .agentignore |
| External content untrusted | OK | SOUL.md rule 8 (expanded, spec 5.10) |
| Prompt-injection defenses present | OK | SOUL.md rule 8 + references/prompt-injection-defense.md |
| Container/sandbox available | OK | docker + sandbox/Dockerfile + run-sandbox.sh + bwrap-shell.sh |
| WSL export backup exists | ACTION | none found; PowerShell: wsl --export Ubuntu ubuntu-backup-2026-08-03.tar |

## Non-Coding Use

| Item | Status | Evidence / action |
|---|---|---|
| Document parsing tools installed | ACTION | pandoc/poppler/soffice missing: sudo apt install -y pandoc poppler-utils python3-docx python3-openpyxl csvkit duckdb lnav (optional: libreoffice-core libreoffice-writer-nogui) |
| Log analysis tools installed | ACTION | lnav/duckdb missing (same install command) |
| Report output directory defined | OK | ~/agent/reports/ + scripts/new-report.sh + templates/report.md |
| Research mode: citation + uncertainty | OK | references/research-workflow.md |
| System admin mode: read-only diagnostics | OK | references/sysadmin-readonly.md + narrow sudoers example |

## To reach fully green

1. sudo apt update && sudo apt upgrade   (18 pending)
2. Create .wslconfig with [wsl2] memory/processors, then wsl --shutdown
3. wsl --export Ubuntu ubuntu-backup-2026-08-03.tar   (PowerShell)
4. sudo apt install -y pandoc poppler-utils python3-docx python3-openpyxl csvkit duckdb lnav
5. Optional: GPG key for commit signing; trash-cli; gitleaks/trufflehog
