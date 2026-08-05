# Zero-Trust Remediation & Hardening — 2026-08-05

Status: **APPLIED + verified on this machine.** Scope: kernel/container boundaries,
sudoers, input validation, audit reliability, live config deny list.
Follow-up required: Test 4 (sudoers apply — user action, see §7).

## 1. Sandboxing layer (Phase 1)

### `scripts/bwrap-shell.sh` — rewrite
- Refuses to run from `$HOME`, `$HOME/`, or `/` (broad host exposure guard).
- Sensitive dirs masked with empty tmpfs **after** `--bind "$PWD"` (last mount wins —
  fixes the mount-order bypass where a bind of PWD overlaid the masks).
- Mask dirs: `~/.ssh` `~/.aws` `~/.azure` `~/.config/gcloud` `~/.gnupg` `~/.kube` `~/.docker`
  (only when present). Mask files (bind `/dev/null`): `~/.netrc`, `~/.bash_history`,
  `~/.zsh_history`, `~/.python_history` (only when present).
- Network isolated by default (`--unshare-net`); `SANDBOX_NET=1` opts in.
  Legacy `SANDBOX_NO_NET=1` is now the default behavior (accepted, no-op).
- Adds `--unshare-ipc`, `--new-session`, `--chdir "$PWD"`, fresh tmpfs `/tmp` + `/var/tmp`.
- **Documented deviation from spec:** `--tmpfs /workspace` mounts only when
  `/workspace` exists on the host — bwrap cannot create mount points under a
  read-only root (verified: `bwrap: Can't mkdir /workspace: Read-only file system`).
  `/tmp` and `/var/tmp` always provide fresh writable scratch.
- Verified: dummy `~/.ssh/id_rsa` masked inside sandbox (`No such file or directory`),
  `~/.bash_history` → 0 bytes, `/tmp` empty, PWD rw bind works; refusal from `$HOME`
  and `/` exits 1 with FATAL.

### `scripts/run-sandbox.sh` — rewrite
- `NETWORK=host` is now a **hard FATAL block** (was a warning; container shares host netns).
- `--cap-drop ALL` (verified `CapEff: 0000000000000000`).
- `--read-only` rootfs (verified: `touch /rootfs-test` → EROFS).
- `--tmpfs /tmp:rw,noexec,nosuid,size=512m` + `--scratch /scratch:rw,noexec,nosuid,size=1g`
  (verified writable).
- Host `$PWD` mounts at `/work` **read-only by default**; `SANDBOX_RW=1` opts in to rw
  (verified: `touch /work/test_write.txt` → EROFS).
- Interactive run verified via pty: container bash prompt, clean exit 0.

### `sandbox/Dockerfile` — patch
- Exact version pins → major.minor wildcards (`git=1:2.53.*`, `python3=3.14.*`,
  `nodejs=22.*`, `npm=9.*`, `jq=1.8.*`, `ripgrep=15.*`; `build-essential` unpinned).
  Fixes apt-get 404 during disaster recovery when a repo bumps versions.
- Verified: apt accepts wildcard versions; image rebuilt 2026-08-05 →
  git 2.53.0, python3 3.14.4, node v22.22.1, npm 9.2.0, jq 1.8.1, rg 15.1.0, gcc 15.2.0.

## 2. Sudoers (Phase 2)

- `references/sudoers-hermes-readonly.example`: `NOPASSWD:` → `NOEXEC: NOPASSWD:` —
  blocks pager-based shell escapes (`!/bin/sh`) inside `systemctl`/`journalctl`.
- NOTE: NOEXEC also blocks the pager itself (less) — output falls back to plain stdout.
- **NOT YET APPLIED to `/etc/sudoers.d`** — user action required (see §7).

## 3. Input validation (Phase 3)

- `scripts/assemble-prompt.sh`: persona allow-list `^[a-zA-Z0-9_-]+$`
  (verified FATAL exit 1 on `../../etc/cron.d/malicious`; valid persona still works).
- `scripts/prompt-aliases.sh`: `_validate_persona` applied to all aliases + `hermes-one`
  (verified FATAL on `../../etc/passwd`).
- `scripts/hermes-project-init`: allow-list `^[a-zA-Z0-9][a-zA-Z0-9._-]*$` replaces
  `basename` (verified FATAL on `..` and `foo/../../etc`; positive path works, temp HOME).
- `scripts/trash.sh`: `date +%s%N` + collision loop (fixes same-second silent overwrites).

## 4. Audit & operational reliability (Phase 4)

- `scripts/readiness-check.sh`:
  - `HERMES_HOME` default: round 1 moved `~/.hermes` → `~/.config/hermes`
    (machine-specific); **round 2 (2026-08-05 runbook, C5) reverted to
    `~/.hermes`** — the canonical platform default per `hermes_constants.py`
    `_get_platform_default_hermes_home()`. `HERMES_HOME` env override wins on
    this machine (`~/.config/hermes` in `.bashrc`), so runtime is unchanged.
  - Added startup WARN when the resolved `HERMES_HOME` does not exist.
  - Deny-list count: `len(deny)` → `len(deny) if isinstance(deny, list) else 0`
    (a scalar-coerced list previously counted characters → false PASS; now 0 → FAIL).
  - Regex fallback now also handles flow-style `deny: [...]` (old block-only regex
    returned 0 on flow style).
  - New check: `prompts/base.md` symlink resolves.
- `scripts/setup-logrotate.sh`: fixed `/tmp/hermes-logrotate` → `mktemp` (predictable
  /tmp symlink attack), `HERMES_HOME` default fixed.

## 5. Live config deny list (Phase 5)

- `~/.config/hermes/config.yaml` `approvals.deny`: 27 → **39 patterns** (round 1),
  39 → **47 patterns** (round 2, B2), **47 → 71 patterns (round 3, R-02)**.
  Round-3 additions: shell/interpreter wrappers (`bash -c *`, `python3 -c *`,
  `perl -e *`, …), absolute-path binaries (`/bin/rm -rf *`, `/usr/bin/find / -delete*`),
  flag reorders (`rm -r -f *`, `rm -f -r *`), subshell prefixes (`(sudo *`, `(rm -rf *`),
  `find / -exec sudo *`, `find /home -delete*`, `env rm -rf *`, `eval *`, `exec sudo *`).
- Written as real YAML list (never `hermes config set`). Backups:
  `/tmp/hermes-config.yaml.pre-remediation.bak` (r1),
  `/tmp/hermes-config.yaml.pre-b2.bak` (r2), `/tmp/hermes-config.yaml.pre-r02.bak` (r3).
  Recovery script in README §Phase 5 updated to restore the full 71-pattern list.
- `approvals.smart_policy` gained rule 9 (r3): invoke `scripts/hardline-check.sh`
  pre-execution on any command not already deny-listed.
- `prompts/base.md` symlink: claim of dangling symlink was **stale** — it already
  resolved to `../SOUL.md`; the new audit check guards it going forward.

## 6. Verification evidence

| Test | Result |
|---|---|
| bwrap credential mask (`~/.ssh/id_rsa`) | PASS — hidden by tmpfs |
| bwrap history mask (`~/.bash_history`) | PASS — 0 bytes |
| bwrap fresh `/tmp` | PASS — empty |
| bwrap refusal from `$HOME` / `/` | PASS — FATAL, exit 1 |
| docker `NETWORK=host` | PASS — FATAL, exit 1 |
| docker ro `/work` mount | PASS — EROFS |
| docker rootfs read-only | PASS — EROFS |
| docker capabilities | PASS — CapEff 0000000000000000 |
| docker tmpfs scratch writable | PASS |
| traversal: project-init `..` / `foo/../../etc` | PASS — FATAL |
| traversal: assemble-prompt `../../etc/cron.d/malicious` | PASS — FATAL |
| traversal: hermes-one `../../etc/passwd` | PASS — FATAL |
| audit type-safety: scalar deny | PASS — 0 patterns (FAIL, no false PASS) |
| audit fallback regex: block style | PASS — 27 patterns |
| audit fallback regex: flow style | PASS — 3 patterns |
| Dockerfile wildcard pins (rebuild) | PASS — all toolchains resolve |
| Full readiness audit | 35 pass, 1 fail (env apt drift), 9 info → **43 pass, 0 fail, 11 info (2026-08-06, r3)** |

## 8. Round-3 remediation record (2026-08-06, R-01..R-23)

- **R-01**: apt drift reclassified FAIL → INFO (environmental, not config); audit
  exit-0-iff-FAIL=0 is now truthful; Phase 6b backup cross-ref added to README.
- **R-02**: deny list 47 → 71 (wrapper/path/flag variants); new
  `scripts/hardline-check.sh` shell-layer scanner (pipe-to-shell, base64-to-shell,
  remote-fetch substitution, eval/exec, root-rm via variables); smart_policy rule 9.
- **R-03**: `trash.sh` gates on the CANONICAL path (`realpath` of the parent) —
  `/home/nika/../../etc/passwd` embedded-traversal and symlinked-dir vectors closed.
- **R-04**: `run-sandbox.sh` adds `--memory-swap = --memory`, `--pids-limit 256`,
  `--ulimit nofile/nproc`, `,rprivate` mount propagation, and a `SECCOMP_PROFILE`
  drop-in hook (Docker's default seccomp profile remains the baseline).
- **R-05**: `bwrap-shell.sh` adds `--unshare-user` (with preflight probe → FATAL),
  `--unshare-cgroup-try`, `--tmpfs /proc/sys`, `--tmpfs /sys/firmware`, and
  forwards `"$@"` (supports -c). The guide's `--bind /dev/null
  /proc/sysrq-trigger` mask was empirically PROVEN ineffective in this bwrap
  version (the `--proc` mount wins regardless of option order) and removed —
  the real protection is the user namespace: sysrq writes need CAP_SYS_ADMIN
  in the INITIAL userns, so the file is visible but unwritable
  (`echo 1 > /proc/sysrq-trigger` → Permission denied, verified).
  (Guide's `--unshare-cgroup-ns` and `--true` probe were also invalid bwrap
  flags — used the real flags.)
- **R-06**: Dockerfile gains a real `sandbox` user (ARG SANDBOX_UID/GID), `ENV HOME`,
  `USER sandbox`; image rebuilt with host-matched uid; `sandbox/manifest.txt` records
  resolved toolchain versions.
- **R-07/R-08/R-09/R-10/R-15/R-16/R-17**: readiness now verifies live symlink wiring
  (SOUL.md, prompts/), structural YAML deny check (replaces 3 fragile greps),
  docker-daemon/bwrap/userns liveness, `.agentignore` CONTENT (not just existence),
  `approvals.cron_mode=deny` + `security.tirith_enabled=true`, HERMES_HOME existence
  gate + resolved-path print, `.env` 600/400 check.
- **R-13**: `.pre-commit-config.yaml` expanded (gitleaks + shellcheck + yamllint +
  check-yaml/check-symlinks/check-merge-conflict/eof/whitespace); revs verified.
- **R-14**: `setup-logrotate.sh` temp moved out of /tmp to `$HOME`, stanza path
  quoted, checksum printed (guide's EXIT-trap omitted — it would delete the file the
  install command references).
- **R-20/R-23**: SOUL.md carries stable `audit:` markers (validation-required,
  no-secrets, untrusted-input) instead of prose greps, plus an 11th principle
  bounding unbounded operations.
- **R-21/R-22**: `new-report.sh` rejects degenerate names (`.`, `..`, dotfiles);
  `hermes-one` neutralizes the script-level IFS with `local IFS=' '`.
- Verified: readiness **43 pass, 0 fail, 11 info, exit 0**; trash traversal FATAL;
  hardline scanner blocks all 8 bypass vectors; pre-commit hooks run clean;
  sandbox limits live in `docker inspect`; bwrap `id -u` mapped, sysrq/firmware masked.

## 7. Follow-up (user action)

- Apply NOEXEC sudoers (agent cannot sudo by policy):
  `sudo bash -c 'cat ~/src/hermes-config/references/sudoers-hermes-readonly.example > /etc/sudoers.d/hermes-readonly'`
  then `sudo visudo -c`, then verify the pager escape is blocked:
  `sudo systemctl status ssh` → inside pager `!/bin/bash` → "Operation not permitted".
  Rollback: `sudo rm /etc/sudoers.d/hermes-readonly && sudo visudo -c`.

## Rollback (agent-executable)

- Repo changes: `git revert <remediation commit>` (or reset to `HEAD~1` if unpushed).
- Live config: restore `/tmp/hermes-config.yaml.pre-remediation.bak`, or remove the
  trailing 12 deny entries.
- Image: rebuild with the exact-pin Dockerfile from git history.
