# hermes-config

> Production Best-Practices configuration for [Hermes Agent](https://hermes-agent.nousresearch.com/docs/) —
> SOUL.md identity, role personas, a 9-layer security model, sandboxing tooling, an automated
> readiness audit, and a full disaster-recovery runbook. Built and verified on
> **WSL2 / Ubuntu 26.04 LTS + OpenCode Zen (deepseek-v4-flash-free)**.

![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)
![Platform: WSL2 / Ubuntu 26.04](https://img.shields.io/badge/platform-WSL2%20%2F%20Ubuntu%2026.04-brightgreen)
![Hermes Agent v0.19.1](https://img.shields.io/badge/Hermes%20Agent-v0.19.1-blueviolet)
![Model: deepseek-v4-flash-free](https://img.shields.io/badge/model-deepseek--v4--flash--free-informational)
![Audit: 32 PASS / 0 FAIL](https://img.shields.io/badge/audit-32%20PASS%20%2F%200%20FAIL-2ea44f)

---

## Table of Contents

- [🚀 Project Overview & Architecture](#project-overview)
- [🛡️ Security Model](#security-model)
- [📋 1-Click Recovery / Installation Guide](#recovery)
- [🎭 System Prompts & Personas Architecture](#personas)
- [🛠️ Tools and Sandboxing](#tools)
- [📊 Automated Audit Script](#audit)
- [💾 Backup and Disaster Recovery](#backup)
- [References Index](#references)
- [Contributing](#contributing)
- [License](#license)

---

## <a id="project-overview"></a>🚀 Project Overview & Architecture

This repository is the single source of truth for a hardened, production-grade
Hermes Agent installation. Everything here is **version-controlled and machine-checkable**:
if the machine is lost, the whole system can be rebuilt and re-verified with the commands in
[§ 1-Click Recovery](#recovery).

### Stack

| Layer | Choice | Verified on this machine |
|---|---|---|
| OS | WSL2, Ubuntu 26.04 LTS (Resolute Raccoon), systemd | kernel `6.18.33.2-microsoft-standard-WSL2` |
| Agent | Hermes Agent v0.19.1 (git install, pinned) | `~/.hermes/hermes-agent` |
| Model provider | OpenCode Zen (`opencode-zen`) | `https://opencode.ai/zen/v1`, `api_mode: chat_completions` |
| Model | `deepseek-v4-flash-free` | set via `hermes model` |
| Config home | `$HERMES_HOME = ~/.config/hermes` | active profile: `default` |
| Containers | Docker 29.1.3 (systemd) + `hermes-sandbox` image | user in `docker` group |
| Shell sandbox | bubblewrap (`/usr/bin/bwrap`) | installed |
| Version control | git, branch `main`, identity `NikaNats <nika.nacvlishvili1@gmail.com>` | global + repo-local |

### How the pieces fit together

```
                    ┌────────────────────────────────────────────────┐
   Windows host     │  WSL2 (Ubuntu 26.04, systemd)                  │
                    │                                                │
   .wslconfig ──────►  memory=12GB, processors=8                     │
   (C:\Users\Nika)  │  /etc/wsl.conf: appendWindowsPath=false        │
                    │                                                │
                    │  ┌──────────────────────────────────────────┐  │
                    │  │  Hermes Agent v0.19.1                    │  │
                    │  │  $HERMES_HOME=~/.config/hermes           │  │
                    │  │  SOUL.md ──symlink──► hermes-config      │  │
                    │  │  prompts/ ──symlink─► hermes-config      │  │
                    │  │  config.yaml: approvals.mode=smart       │  │
                    │  │              approvals.deny: 27 patterns │  │
                    │  │              security.redact_secrets=true│  │
                    │  │  model: opencode-zen / deepseek-v4       │  │
                    │  └──────────────────────────────────────────┘  │
                    │         │  │  │  │                            │
                    │         ▼  ▼  ▼  ▼                            │
                    │  sandbox/  scripts/  references/  ~/agent/    │
                    │  Docker    *.sh      spec docs     reports/   │
                    │  bwrap     tooling   spec docs     artifacts/ │
                    │            helpers                downloads/  │
                    │                                workspaces/    │
                    └────────────────────────────────────────────────┘
```

### Repository layout

```
hermes-config/
├── SOUL.md                     # Base identity & safety charter (auto-loaded)
├── README.md                   # This file — the master guide & runbook
├── .gitignore                  # Secret/credential ignore patterns (spec 5.6)
├── .gitattributes              # LF line endings everywhere (WSL/Windows interop)
├── .pre-commit-config.yaml     # gitleaks secret scan hook (enforced on commit)
├── prompts/                    # Persona library (modular building blocks)
│   ├── base.md -> ../SOUL.md   # Relative symlink — base layer is never duplicated
│   ├── coding.md               # Principal Production Software Engineer
│   ├── review.md               # Staff Code Reviewer
│   ├── ops.md                  # Production SRE / Systems Engineer
│   ├── research.md             # Technical Research Analyst
│   ├── automation.md           # Workflow Automation Engineer
│   └── production.md           # Production Ops persona (spec 6.1)
├── references/                 # Spec 3–7 reference docs (one per section)
│   ├── approval-matrix.md      #   Spec 3.6 approval matrix & defense in depth
│   ├── toolchains.md           #   Spec 3.4 canonical per-language validation
│   ├── document-parsing.md     #   Spec 4.1 DOCX/PDF/CSV tooling
│   ├── log-analysis.md         #   Spec 4.2 log tools & triage workflow
│   ├── sysadmin-readonly.md    #   Spec 4.3 read-only sysadmin + narrow sudoers
│   ├── sudoers-hermes-readonly.example  #   apply manually, never broad sudo
│   ├── research-workflow.md    #   Spec 4.4 research + injection defenses
│   ├── reporting-artifacts.md  #   Spec 4.5 report dir convention & template
│   ├── safety-model.md         #   Spec 5.1 9-layer operational safety model
│   ├── backup-recovery.md      #   Spec 5.2 WSL/config backup + git safety net
│   ├── safe-interaction-patterns.md  #   Spec 5.3 read-only-first, plan, evidence
│   ├── grounding-and-verification.md #   Spec 5.4 anti-hallucination rules
│   ├── destructive-commands.md #   Spec 5.5 destructive command policy + trash
│   ├── secrets-hygiene.md      #   Spec 5.6 credential hygiene + .agentignore
│   ├── audit-logging.md        #   Spec 5.7 audit log schema + logrotate
│   ├── validation-checklist.md #   Spec 5.8 build/lint/test + security scans
│   ├── cicd-guardrails.md      #   Spec 5.9 CI/CD allowed/denied + PR workflow
│   ├── prompt-injection-defense.md   #   Spec 5.10 injection defense block + rules
│   ├── production-profile.md   #   Spec 6.1 blueprint -> real control mapping
│   ├── preflight-checklist.md  #   Spec 6.3 read-only pre-flight before edits
│   └── readiness-checklist.md  #   Spec 7 readiness checklist (snapshot)
├── sandbox/
│   └── Dockerfile              # hermes-sandbox image (ubuntu:26.04, pinned toolchains)
└── scripts/
    ├── assemble-prompt.sh      # Concatenate SOUL.md + persona -> active prompt
    ├── run-sandbox.sh          # Docker sandbox runner (resource/network limits)
    ├── bwrap-shell.sh          # Bubblewrap restricted shell
    ├── new-report.sh           # Dated report artifact creator
    ├── trash.sh                # Trash instead of delete helper
    ├── hermes-project-init     # Safe project bootstrap (spec 6.2)
    ├── readiness-check.sh      # Automated readiness audit (read-only, spec 7)
    ├── prompt-aliases.sh       # Persona activation fns (HERMES_EPHEMERAL_SYSTEM_PROMPT)
    ├── setup-logrotate.sh      # Generates logrotate config + apply command (spec 5.7)
    └── templates/
        ├── report.md           # Markdown report template
        └── safe-script.sh      # Default safe header for generated scripts
```

---

## <a id="security-model"></a>🛡️ Security Model

Defense in depth: **no single layer is sufficient** — every layer maps to a real,
checked artifact in this repo or on the OS (`references/safety-model.md`).

### The 9 layers of protection

| # | Layer | Implementation |
|---|---|---|
| 1 | Prompt rules | `SOUL.md` principles + Safety & Boundaries |
| 2 | Hermes config permissions | `config.yaml` `approvals.*` (deny list, smart policy) |
| 3 | OS user permissions | non-root user `nika` (uid 1000); **no passwordless sudo** |
| 4 | Filesystem boundaries | `~/agent/{reports,artifacts,downloads,workspaces}` + repo tree |
| 5 | Command policy | `references/approval-matrix.md` + `approvals.deny` |
| 6 | Sandbox / container | `sandbox/Dockerfile`, `scripts/run-sandbox.sh`, `scripts/bwrap-shell.sh` |
| 7 | Git / version control | this repo (commit before/after changes) |
| 8 | Human approval | `approvals.mode=smart`; typed confirmation for destructive ops |
| 9 | Audit logs | `~/.config/hermes/logs/{agent.log,errors.log}` + session DB |

Failure model: if one layer fails (a deny pattern too broad or too narrow, a missing
review, a race), the layers above and below still gate the action.

### approvals.deny — 27 forbidden command patterns

Enforced by Hermes at the tool layer: the agent **cannot run** these at all
(verified in `~/.config/hermes/config.yaml`).

| # | Pattern | # | Pattern |
|---|---|---|---|
| 1 | `rm -rf /` | 15 | `git checkout -- .` |
| 2 | `rm -rf ~` | 16 | `git branch -D*` |
| 3 | `sudo *` | 17 | `git rebase -i*` |
| 4 | `chmod -R 777 *` | 18 | `systemctl stop*` |
| 5 | `chown -R *` | 19 | `systemctl disable*` |
| 6 | `curl * \| *sh` | 20 | `iptables -F*` |
| 7 | `wget * \| *sh` | 21 | `docker system prune*` |
| 8 | `git push --force*` | 22 | `kubectl delete*` |
| 9 | `git reset --hard*` | 23 | `terraform destroy*` |
| 10 | `git clean -fd*` | 24 | `pulumi destroy*` |
| 11 | `dd if=*` | 25 | `ansible-playbook --check=false*` |
| 12 | `mkfs*` | 26 | `fdisk /dev*` |
| 13 | `shutdown*` | 27 | `parted /dev*` |
| 14 | `reboot*` | | |

Notes (from `references/destructive-commands.md`):

- `git push --force-with-lease` is covered by the `git push --force*` pattern.
- `rmdir /s` (Windows cmd) is irrelevant to WSL bash and is not matched.
- SQL destructive statements (`DROP TABLE`, `TRUNCATE`, `DELETE FROM` without `WHERE`)
  and production `systemctl stop/disable` cannot be caught by prefix matching — they are
  **policy-only**: the agent must propose a reviewable plan and the human runs them.
- The agent cannot invoke `sudo` at all (deny `sudo *`); narrow passwordless read-only
  diagnostics can be enabled for the **user** only via
  `references/sudoers-hermes-readonly.example` (apply with `sudo visudo -c` yourself).

### smart_policy — production shell policy

When `approvals.mode=smart`, Hermes consults this policy before running shell commands.
Current value in `config.yaml`:

```text
Production shell policy. Guardian MUST follow:
1. DENY sudo.
2. DENY rm -rf except on scoped temp/build paths the agent explicitly names.
3. DENY piping remote scripts into a shell (curl | sh, wget | sh).
4. DENY force-push (git push --force*) and history rewrite (git reset --hard*, git clean -fd*).
5. DENY raw device writes (dd if=*), filesystem creation (mkfs*), and system power commands (shutdown*, reboot*).
6. DENY wholesale permission changes (chmod -R 777 *, chown -R *).
7. APPROVE read-only git (status/diff/log) and test/lint commands (pytest, npm test, npm run lint, ruff, cargo test, go test) without escalation.
8. ESCALATE anything touching /etc, /boot, /root, or global shell configs, and destructive deletions outside the working tree.
```

Supporting config (all verified live):

```yaml
approvals:
  mode: smart          # explicit tool permissions; destructive ops need typed confirmation
  cron_mode: deny      # scheduled jobs cannot run unapproved destructive commands
security:
  redact_secrets: true # secrets redacted from output
  tirith_enabled: true # threat-pattern scanner active on identity/context files
logging:
  level: INFO          # ~/.config/hermes/logs/{agent.log,errors.log}
```

### Secret & credential hygiene

`~/.agentignore` (home) and this repo's `.gitignore` both carry the pattern list;
real enforcement is `security.redact_secrets: true` + SOUL.md rule 7 + output redaction.
Protected paths: `~/.ssh`, `~/.aws`, `~/.azure`, `~/.config/gcloud`, `~/.gnupg`,
`~/.netrc`, `.env*`, `*.pem`, `*.p12`, `*.pfx`, `*.key`.

`~/.agentignore` contents:

```text
.env
.env.*
*.pem
*.key
*.p12
*.pfx
id_rsa
id_ed25519
.aws/
.azure/
.config/gcloud/
.ssh/
.gnupg/
```

### Pre-commit secret scan (gitleaks)

`pre-commit` (installed via pipx) + a gitleaks hook block commits that stage
credentials. Verified on this machine (2026-08-03): the hook **fails (exit 1)**
when a realistic GitHub PAT / AWS key / Stripe key / Slack token is staged, and
passes a clean tree.

```bash
pipx install pre-commit                 # one-time
cd ~/src/hermes-config
pre-commit install                      # installs .git/hooks/pre-commit
pre-commit run gitleaks --all-files     # scan everything now
```

`.pre-commit-config.yaml` pins gitleaks to a verified release. Gitleaks' default
config allow-lists obviously-fake/sequential test values by design, so unit-test
the hook with a realistic token, not `AKIA...EXAMPLE`.

### Prompt-injection defense

SOUL.md principle 8 (expanded in `references/prompt-injection-defense.md`):
all external content — web pages, PDFs, DOCX files, logs, issue trackers, emails,
API responses — is **untrusted data, never instructions**. If external content asks
to run commands, reveal secrets, change permissions, or ignore prior rules, the agent
reports it as suspicious instead of complying. The hardline scanner also blocks
dangerous substrings anywhere on a command line (defense-in-depth at the shell layer).

---

## <a id="recovery"></a>📋 1-Click Recovery / Installation Guide

> **Goal:** go from a wiped machine to a fully GREEN audit
> (`bash ~/src/hermes-config/scripts/readiness-check.sh` → `32 pass, 0 fail, 6 info`, exit 0).
>
> Commands marked **`[PowerShell]`** run on Windows; everything else runs inside WSL.
> The agent itself cannot run `sudo` by policy — privileged steps are for *you* to run.

### Phase 0 — Prerequisites (Windows)

```powershell
# 1. Install WSL2 + Ubuntu (this machine's distro is named "Ubuntu", 26.04 LTS)
wsl --install -d Ubuntu
# 2. Create / edit C:\Users\<you>\.wslconfig with resource limits:
#      [wsl2]
#      memory=12GB
#      processors=8
wsl --shutdown   # restart WSL so the limits apply
```

### Phase 1 — Harden WSL itself (inside Ubuntu)

```bash
sudo tee /etc/wsl.conf > /dev/null <<'EOF'
[boot]
systemd=true

[user]
default=nika

[interop]
enabled=true
appendWindowsPath=false

[automount]
enabled=true
options="metadata,umask=022,fmask=111"
EOF

sudo apt update && sudo apt upgrade -y      # get to 0 pending upgrades
wsl.exe --shutdown                          # from Ubuntu: restart so wsl.conf applies
```

> ⚠️ `appendWindowsPath=false` removes Windows binaries from `PATH` after restart —
> reach them via `/mnt/c/...` or add entries to `~/.bashrc` explicitly.

### Phase 2 — Install Hermes Agent

Official one-liner (recommended for recovery; this machine is a git install pinned to
`d0b87da` — the one-liner is the supported path):

```bash
curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash
```

Verify:

```bash
hermes --version      # e.g. "Hermes Agent v0.19.1"
hermes doctor         # config health check
```

### Phase 3 — Configure the model provider (OpenCode Zen)

```bash
hermes setup          # interactive wizard: pick provider "opencode-zen"
hermes model          # set model: deepseek-v4-flash-free
```

Add credentials to `~/.config/hermes/.env` (key **names** used on this machine —
values are secret and never committed):

```text
OPENCODE_ZEN_API_KEY=<your-key>
OPENCODE_ZEN_BASE_URL=https://opencode.ai/zen/v1
```

Resulting `model:` block in `config.yaml`:

```yaml
model:
  api_mode: chat_completions
  base_url: https://opencode.ai/zen/v1
  default: deepseek-v4-flash-free
  provider: opencode-zen
```

### Phase 4 — Clone this repository and wire the symlinks

```bash
mkdir -p ~/src ~/agent/{reports,artifacts,downloads,workspaces}

# After the repo is on GitHub (see "Publish this repo", below):
git clone https://github.com/<your-gh-user>/hermes-config.git ~/src/hermes-config

# Live wiring (symlinks — edits land in the repo, changes apply to NEW sessions):
ln -sf ~/src/hermes-config/SOUL.md   ~/.config/hermes/SOUL.md
ln -sf ~/src/hermes-config/prompts   ~/.config/hermes/prompts
ln -sf ~/src/hermes-config/SOUL.md   ~/.hermes/SOUL.md        # legacy home, if present

# One-time convenience symlinks:
ln -sf ~/src/hermes-config/scripts/hermes-project-init ~/bin/hermes-project-init
```

### Phase 5 — Restore `config.yaml` (approvals + security)

> ⚠️ **Never set list keys with `hermes config set`** — it coerces scalars only and a
> `*` inside a scalar deny entry matches *every* command (fnmatch iterates characters),
> locking the terminal. Write list keys as real YAML (backup first, Hermes not running):

```bash
cp ~/.config/hermes/config.yaml ~/.config/hermes/config.yaml.bak

python3 - <<'PY'
import yaml
p = '/home/nika/.config/hermes/config.yaml'
cfg = yaml.safe_load(open(p)) or {}
cfg['approvals'] = {
    'mode': 'smart',
    'cron_mode': 'deny',
    'deny': [
        'rm -rf /', 'rm -rf ~', 'sudo *',
        'chmod -R 777 *', 'chown -R *',
        'curl * | *sh', 'wget * | *sh',
        'git push --force*', 'git reset --hard*', 'git clean -fd*',
        'dd if=*', 'mkfs*', 'shutdown*', 'reboot*',
        'git checkout -- .', 'git branch -D*', 'git rebase -i*',
        'systemctl stop*', 'systemctl disable*', 'iptables -F*',
        'docker system prune*', 'kubectl delete*',
        'terraform destroy*', 'pulumi destroy*',
        'ansible-playbook --check=false*', 'fdisk /dev*', 'parted /dev*',
    ],
    'smart_policy': (
        'Production shell policy. Guardian MUST follow:\n'
        '1. DENY sudo.\n'
        '2. DENY rm -rf except on scoped temp/build paths the agent explicitly names.\n'
        '3. DENY piping remote scripts into a shell (curl | sh, wget | sh).\n'
        '4. DENY force-push (git push --force*) and history rewrite (git reset --hard*, git clean -fd*).\n'
        '5. DENY raw device writes (dd if=*), filesystem creation (mkfs*), and system power commands (shutdown*, reboot*).\n'
        '6. DENY wholesale permission changes (chmod -R 777 *, chown -R *).\n'
        '7. APPROVE read-only git (status/diff/log) and test/lint commands (pytest, npm test, npm run lint, ruff, cargo test, go test) without escalation.\n'
        '8. ESCALATE anything touching /etc, /boot, /root, or global shell configs, and destructive deletions outside the working tree.'
    ),
}
cfg['security'] = {'redact_secrets': True, 'tirith_enabled': True}
cfg['logging'] = {'level': 'INFO'}
yaml.safe_dump(cfg, open(p, 'w'), sort_keys=False, default_flow_style=False)
PY

hermes config get approvals.mode          # -> smart
hermes config get security.redact_secrets # -> true
```

Restore `~/.agentignore` (contents in [§ Security Model](#security-model)):

```bash
cat > ~/.agentignore <<'EOF'
.env
.env.*
*.pem
*.key
*.p12
*.pfx
id_rsa
id_ed25519
.aws/
.azure/
.config/gcloud/
.ssh/
.gnupg/
EOF
```

### Phase 6 — System tooling (sandbox, docs, logs)

```bash
# Container sandbox + docker group (already set up on this machine):
sudo apt install -y docker.io
sudo usermod -aG docker "$USER"      # re-login after

# Build the sandbox image (once):
docker build -t hermes-sandbox ~/src/hermes-config/sandbox/

# Bubblewrap restricted shell:
sudo apt install -y bubblewrap

# Document / log analysis tooling (turns the 2 INFO notes into PASS):
sudo apt install -y pandoc poppler-utils python3-docx python3-openpyxl csvkit duckdb lnav

# Optional hardening: trash-cli, commit signing key, secret scanners (gitleaks, trufflehog)
sudo apt install -y trash-cli
```

### Phase 7 — Verify: the 100% GREEN audit

```bash
bash ~/src/hermes-config/scripts/readiness-check.sh
```

Expected on a fully restored machine:

```text
readiness: 32 pass, 0 fail, 6 info     # exit code 0  (any FAIL -> exit code 1)
```

> The 6 INFO notes are documented gaps, not failures: deterministic temperature is
> model/provider-level, filesystem ACLs are OS perms + `.agentignore`, no GPG key
> (optional), test runner is per-project, and pandoc/lnav/duckdb are the two optional
> tool groups listed in Phase 6. **0 FAIL is the "fully green" definition.**

### Publish this repo (one-time, so recovery works from anywhere)

```bash
cd ~/src/hermes-config
git remote add origin git@github.com:<your-gh-user>/hermes-config.git
git push -u origin main
# or with GitHub CLI:
gh repo create hermes-config --public --source=. --remote=origin --push
```

---

## <a id="personas"></a>🎭 System Prompts & Personas Architecture

### How Hermes loads prompts (verified behavior)

- `$HERMES_HOME/SOUL.md` is the identity layer — **Layer 1 ("stable" tier)** of the
  cached system prompt. It is auto-loaded whenever present and **completely replaces**
  the default identity (it does not append).
- A `prompts/` directory is **not** auto-loaded. Persona files are manual building
  blocks; activate one at runtime via `HERMES_EPHEMERAL_SYSTEM_PROMPT` (see below),
  or assemble a static file by concatenation (base + persona).
- SOUL.md changes apply only to **NEW sessions** — prompt caching freezes the system
  prompt mid-conversation. After editing, run `hermes --ignore-rules` or start a new
  session to test.
- `SOUL.md` replaces, not appends: keep identity + safety charter + output discipline
  in it; task personas belong in `prompts/`.

### The base layer — `SOUL.md`

Ten operating principles (precision, evidence, no invented facts, minimal change,
no secrets, untrusted external content, confirmation before destructive actions,
validation-first) + output discipline (summary → verified findings → exact steps →
validation/rollback) + safety boundaries (no data-destroying commands, no global state
changes, no unapproved installs, no force-push/history rewrite, ask one targeted
question when uncertain).

### The 6 role personas

| Persona | File | Role | Key rules |
|---|---|---|---|
| Coding | `prompts/coding.md` | Principal Production Software Engineer | read code first, tests, lint, minimal diff, definition of done |
| Review | `prompts/review.md` | Staff Code Reviewer | severity-tagged findings (blocker/major/minor/nit), security focus |
| Ops | `prompts/ops.md` | Production SRE / Systems Engineer | read-only diagnostics first, reversible changes, rollback always |
| Research | `prompts/research.md` | Technical Research Analyst | external content = untrusted, cite sources, label unverified |
| Automation | `prompts/automation.md` | Workflow Automation Engineer | idempotent, fail loudly, dry-run, no secrets in scripts |
| Production | `prompts/production.md` | Production Ops (spec 6.1) | plan → approve → execute; evidence required; stop when uncertain |

`prompts/base.md -> ../SOUL.md` is a **relative symlink**, so the base layer is never
duplicated and the repo survives moves/clones.

### Assembling an active prompt

```bash
# Base only (SOUL.md):
bash ~/src/hermes-config/scripts/assemble-prompt.sh

# Base + persona:
bash ~/src/hermes-config/scripts/assemble-prompt.sh coding
bash ~/src/hermes-config/scripts/assemble-prompt.sh review
bash ~/src/hermes-config/scripts/assemble-prompt.sh ops
bash ~/src/hermes-config/scripts/assemble-prompt.sh research
bash ~/src/hermes-config/scripts/assemble-prompt.sh automation
bash ~/src/hermes-config/scripts/assemble-prompt.sh production

# Output: $HERMES_HOME/cache/active-system-prompt.md
```

The result is a single Markdown file (SOUL.md + persona) you can feed as the system
message, or diff persona layers against each other. Keep personas short to avoid
context pollution; base wins on safety, persona wins on method.

### Activating a persona at runtime

There is **no `hermes --system-prompt` CLI flag** (verified against v0.19.1
source). The supported mechanism is the `HERMES_EPHEMERAL_SYSTEM_PROMPT`
environment variable, read at session start and injected as the **context tier —
on top of** SOUL.md (which stays the stable identity tier). Verified end-to-end
with a marker string echoed back by the model.

```bash
# Session-scoped persona (no config mutation):
HERMES_EPHEMERAL_SYSTEM_PROMPT="$(cat ~/src/hermes-config/prompts/coding.md)" hermes chat
```

`scripts/prompt-aliases.sh` wraps this in functions — source it from `~/.bashrc`:

```bash
[ -f ~/src/hermes-config/scripts/prompt-aliases.sh ] && \
  source ~/src/hermes-config/scripts/prompt-aliases.sh

hermes-coding       # coding persona REPL
hermes-review       # review persona REPL
hermes-ops          # ops persona REPL
hermes-research     # research persona REPL
hermes-automation   # automation persona REPL
hermes-production   # production persona REPL
hermes-base         # plain SOUL.md-only session
hermes-one coding "implement the auth module"   # one-shot with persona
```

Persistent alternative: register entries under `agent.personalities` in
`config.yaml`, then use the `/personality <name>` slash command in-session
(that writes `agent.system_prompt` into the config — it persists across sessions).

### Edit → commit → live cycle

1. Edit canonically in `~/src/hermes-config` (symlinks make it live for new sessions).
2. Commit with `type(scope): summary` messages; review prompt changes like code changes.
3. Verify with `hermes doctor` and, for this repo, `scripts/readiness-check.sh`.

---

## <a id="tools"></a>🛠️ Tools and Sandboxing

| Tool | What it does | Usage |
|---|---|---|
| `scripts/run-sandbox.sh` | Runs risky work in a Docker container (`hermes-sandbox`): `--init`, non-root user, `no-new-privileges`, memory/CPU limits, **no outbound network by default** | `bash scripts/run-sandbox.sh` |
| `scripts/bwrap-shell.sh` | Bubblewrap restricted shell: read-only root, tmpfs over `~/.ssh`/`~/.aws`/`~/.config/gcloud`, private pid/uts namespaces, dies with parent | `bash scripts/bwrap-shell.sh` |
| `scripts/trash.sh` | Move to `~/.local/share/Trash/files/` instead of deleting (timestamped, never overwrites) | `bash scripts/trash.sh <path>...` |
| `scripts/new-report.sh` | Create a dated report under `~/agent/reports/YYYY-MM-DD/` from the template | `bash scripts/new-report.sh <name>` |
| `scripts/hermes-project-init` | Bootstrap `~/src/<name>` + `~/agent/workspaces/<name>` with git init + `.agentignore` | `bash scripts/hermes-project-init <name>` |
| `scripts/assemble-prompt.sh` | Concatenate SOUL.md + persona into the active prompt | see [§ Personas](#personas) |
| `scripts/readiness-check.sh` | Read-only production readiness audit (see [§ Audit](#audit)) | `bash scripts/readiness-check.sh` |
| `scripts/prompt-aliases.sh` | Persona activation functions via `HERMES_EPHEMERAL_SYSTEM_PROMPT` | source it, then `hermes-coding` etc. |
| `scripts/setup-logrotate.sh` | Generates `/tmp/hermes-logrotate` + prints the exact `sudo install` command (agent can't sudo) | `bash scripts/setup-logrotate.sh` |
| `sandbox/Dockerfile` | `hermes-sandbox` image: Ubuntu 26.04 (host parity) + pinned git 2.53, python3 3.14, node 22, jq, ripgrep | `docker build -t hermes-sandbox sandbox/` |

### Docker sandbox details

`run-sandbox.sh` env overrides: `HERMES_SANDBOX_IMAGE` (default `hermes-sandbox`),
`NETWORK` (`none` | `bridge` | `host`, default `none` — no outbound network),
`MEM_LIMIT` (default `4g`), `CPU_LIMIT` (default `2`). Mounts `$PWD` at `/work`.
Build once with `docker build -t hermes-sandbox ~/src/hermes-config/sandbox/`
(verified: builds and runs on this machine, 2026-08-03).

Base image is `ubuntu:26.04` — identical to the WSL2 host, eliminating
"works on my machine" drift. Toolchain versions are pinned and were verified
against the ubuntu:26.04 apt repo (git 2.53.0, python3 3.14.4, nodejs 22.22.1,
npm 9.2.0, jq 1.8.1, ripgrep 15.1.0). Relax a pin if a distro update bumps the
version — or use `apt-get install -y <pkg>` unpinned.

Use it for: dependency installs, untrusted code, experiments. Never for credentials.

### Bubblewrap details

Additive layer only (not a full container): read-only `/`, tmpfs `/tmp`, sensitive
dirs shadowed with empty tmpfs when present, `--unshare-pid/--uts`, `--die-with-parent`.
Requires bubblewrap + user namespaces in the kernel.

### Report artifacts & safe script header

- `scripts/new-report.sh <name>` → `~/agent/reports/<date>/<name>.md` (template:
  Summary / Evidence / Findings / Risks / Recommended Actions / Follow-up Commands).
- `scripts/templates/safe-script.sh` — default header for generated scripts:
  `set -Eeuo pipefail`, `timeout` wrappers, `--dry-run` where available, no `eval`,
  no `curl | sh`, no `sudo`, no scoped `rm -rf` without review.

### Reference toolchains

`references/toolchains.md` documents canonical validation commands per ecosystem
(uv/Python, npm/pnpm/Node, cargo/Rust, go, Docker) — always prefer the project's own
tooling before inventing commands.

---

## <a id="audit"></a>📊 Automated Audit Script

`scripts/readiness-check.sh` is a **read-only** machine audit (spec 7). It never
modifies anything; it prints `PASS/FAIL/INFO` per item and exits `0` when there is no
FAIL, `1` when any item FAILs.

```bash
bash ~/src/hermes-config/scripts/readiness-check.sh
```

### What it checks (38 checks — latest verified result: 32 PASS / 0 FAIL / 6 INFO)

| Section | PASS | INFO | Sample checks |
|---|---:|---:|---|
| WSL Environment | 7 | 0 | WSL2 kernel, distro updated, systemd, non-root user, `.wslconfig` limits, `appendWindowsPath=false`, `~/src` on ext4 |
| Hermes Configuration | 7 | 2 | config versioned, prompts modular, `approvals.mode=smart`, deny list ≥ 27, `.agentignore`+`.gitignore`, `redact_secrets`, logs present |
| Coding Workflow | 6 | 2 | git identity, branching strategy, linters present, validation required by SOUL.md, backup procedure defined |
| Safety | 9 | 0 | no passwordless sudo, `sudo *` denied, no broad `rm -rf`, no force-push, no secret access, untrusted-content rule, injection defenses, sandbox present, WSL export backup exists |
| Non-Coding Use | 3 | 2 | report dir, research mode, sysadmin mode (doc/log tools are optional INFO) |

The live reference for the human-readable checklist is `references/readiness-checklist.md`;
the script is the source of truth — the doc is a snapshot.

### Re-run cadence

Run the audit before letting Hermes do real work, after any system change, and as the
final step of every recovery/restore. A commit to this repo should always be able to
say "readiness: 32 pass, 0 fail".

---

## <a id="backup"></a>💾 Backup and Disaster Recovery

### WSL full-machine snapshot (Windows PowerShell)

```powershell
# Export (while the distro is shut down for a consistent image):
wsl --shutdown
wsl --export Ubuntu C:\Users\Nika\ubuntu-backup-<date>.tar
```

Current verified backup: `C:\Users\Nika\ubuntu-backup-2026-08-03.tar`.

WSL does **not** overwrite in place — restore into a new distro name:

```powershell
wsl --import UbuntuRestored C:\WSL\UbuntuRestored C:\Users\Nika\ubuntu-backup-2026-08-03.tar
```

> The audit script checks for `ubuntu-backup-*.tar` under `$HOME` or
> `/mnt/c/Users/*/` — keep the export in a known place or the audit FAILs.

### Git as the primary safety net (before agent edits)

```bash
cd ~/src/hermes-config
git status && git diff               # inspect first
git stash push -m "before-hermes-change" || true
git switch -c hermes/task-description   # prefer a branch over editing main
```

Rollback of an agent change = `git revert` / `git reset --soft` / branch delete.
Only for local, unpushed work; never force-push shared history (denied by policy anyway).

### Disaster recovery sequence (summary)

1. Recreate WSL2 Ubuntu (Phase 0–1 of [§ Recovery](#recovery)).
2. Install Hermes + OpenCode Zen credentials (Phase 2–3).
3. Clone this repo, re-wire symlinks, restore `config.yaml` + `.agentignore` (Phase 4–5).
4. Install system tooling (Phase 6).
5. `bash ~/src/hermes-config/scripts/readiness-check.sh` → **32 pass, 0 fail** (Phase 7).
6. Re-import the WSL tar if you want the old filesystem state, or restore project data
   from git remotes.

---

## <a id="references"></a>References Index

Each `references/*.md` is one spec section (3–7), kept current with the live machine:

| Spec | File | One-liner |
|---|---|---|
| 3.4 | `toolchains.md` | canonical per-language validation commands |
| 3.6 | `approval-matrix.md` | what the agent may do without confirmation |
| 3.8–3.9 | `sandbox/Dockerfile`, `run-sandbox.sh`, `bwrap-shell.sh` | container/bubblewrap sandboxing |
| 4.1 | `document-parsing.md` | DOCX/PDF/CSV tooling + analysis prompt |
| 4.2 | `log-analysis.md` | log triage workflow + prompt |
| 4.3 | `sysadmin-readonly.md` + `sudoers-hermes-readonly.example` | read-only sysadmin + narrow sudoers |
| 4.4 | `research-workflow.md` | citation + uncertainty research mode |
| 4.5 | `reporting-artifacts.md` + `templates/report.md` | dated report artifacts |
| 5.1 | `safety-model.md` | the 9-layer model |
| 5.2 | `backup-recovery.md` | WSL/config backup + git safety net |
| 5.3 | `safe-interaction-patterns.md` | read-only-first / plan / evidence / small-diff / stop |
| 5.4 | `grounding-and-verification.md` | anti-hallucination rules |
| 5.5 | `destructive-commands.md` + `trash.sh` | destructive command policy + trash |
| 5.6 | `secrets-hygiene.md` + `.gitignore` | credential hygiene |
| 5.7 | `audit-logging.md` | log schema + logrotate |
| 5.8 | `validation-checklist.md` | build/lint/test + security scans |
| 5.9 | `cicd-guardrails.md` | CI/CD allowed/denied + PR workflow |
| 5.10 | `prompt-injection-defense.md` | injection defense block |
| 6.1 | `production-profile.md` | blueprint → real control mapping |
| 6.2 | `scripts/hermes-project-init` | safe project bootstrap |
| 6.3 | `preflight-checklist.md` | read-only pre-flight before edits |
| 7 | `readiness-checklist.md` + `readiness-check.sh` | production readiness |
| Ext | `hermes-lcm-guide.md` | LCM context-memory plugin: install, config, redaction, upgrade |
| Ext | `codegraph-guide.md` | CodeGraph semantic code-intel MCP: install, index, verify |

---

## <a id="contributing"></a>Contributing

- Prompt changes are code changes: small diffs, explicit rationale, no contradictory
  layers (base wins on safety, persona wins on method).
- Never commit secrets; `.gitignore` / `.agentignore` patterns are enforced policy.
- Before letting Hermes edit this repo, run `scripts/readiness-check.sh` and
  `references/preflight-checklist.md`.
- Commit style: `type(scope): summary` (e.g. `feat(safety): ...`, `docs: ...`).

## <a id="license"></a>License

MIT (as declared in the skill metadata for this repo's components). A `LICENSE` file
should be added before publishing the repository publicly.

---

*Maintained by NikaNats. Last audit: 2026-08-03 — `readiness: 32 pass, 0 fail, 6 info`.*
