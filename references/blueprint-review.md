# Zero-Trust Architecture Blueprint — Claim-by-Claim Review

Revision: R-14 | Verification date: 2026-08-07 | Status on this machine: audited;
safe items implemented (see §4); destructive items pending explicit approval.

Source: external "Hermes Agent Zero-Trust Architecture: Master Implementation
Blueprint" (4 phases). Every claim below was verified against the live files and
system — NOT taken from the document. This file is the audit record.

## 1. Verdict summary

| # | Blueprint claim | Verdict | Evidence |
|---|---|---|---|
| 1.1 | docker group = passwordless host root; remove from group | **TRUE premise, action rejected (needs approval)** | nika IS in docker group; `docker run -v /:/host alpine` passes hardline (exit 0) and approvals.deny (only `docker system prune*` listed). Removal breaks run-sandbox.sh; rootless tooling NOT installed; no passwordless sudo exists for a confined sudo rule |
| 1.2 p1 | block `rm -rf $VAR` / `"${VAR}"` | **ALREADY IMPLEMENTED** | hardline rule 5 already matches `$HOME`, `${VAR}` targets (probe: `rm -rf $HOME/x` → BLOCK) |
| 1.2 p2 | block `base64 -d \| bash` | **ALREADY IMPLEMENTED** | hardline rule 3 blocks decode-to-pipeline; rule 1 blocks pipe-to-shell (probe: `echo x \| base64 -d \| bash` → BLOCK) |
| 1.2 p3 | block `find ... -exec bash/zsh/dash -c` | **REAL GAP — FIXED** | probes: `find / -exec bash -c "rm -rf /etc"` and `find / -exec zsh -c "id"` passed before (exit 0) |
| 1.3.1 | bind Firecrawl to loopback | **TRUE — FIXED** | compose `"${PORT:-3002}:${INTERNAL_PORT:-3002}"` → docker ps showed `0.0.0.0:3002`; now `127.0.0.1:3002` |
| 1.3.2 | ephemeral key script appends to hermes .env | **CORRECTED — script broken as written** | stack validates against TEST_API_KEY in ~/src/firecrawl/.env; rotating only Hermes .env breaks auth. Requires dual-rotation + restart |
| 1.3.3 | git filter-repo purge of dummy key + force-push | **REJECTED** | key is deliberately committed documented dummy (`.gitleaks.toml` header); git-filter-repo NOT installed; repo's own deny-list blocks `git push --force*`; no real secret to purge |
| 2.1 | symlink TOCTOU pre-flight scan | **PARTIAL — scan skipped, real protections exist** | bwrap/run-sandbox use allowlist PWD + re-canonicalize-before-mv (trash.sh) + ro-bind PWD; scan itself uses `find -exec sh -c` — exactly what 1.2 p3 blocks (self-contradiction) |
| 2.1 | NETWORK=none unconditional | **ALREADY IMPLEMENTED** | run-sandbox.sh `NETWORK="${NETWORK:-none}"` (none\|bridge allowlist); bwrap-shell `--unshare-net` default (`SANDBOX_NET=1` opt-in) |
| 2.2 | unset TRASH_FORCE/MAX_BYTES/ALLOW_* + mv -n | **REJECTED (breaks features; already TOCTOU-safe)** | unique-dst loop + re-canonicalize before mv exist (trash.sh 47-56); unset would kill documented opt-ins (TRASH_ALLOW_MOUNTS, TRASH_FORCE) — trash is a move, not a delete |
| 2.3 | whole-agent bwrap wrapper | **DEFERRED — needs design** | mount set excludes state.db (~/.hermes), ~/agent, /tmp, docker socket → breaks the live agent as specced |
| 3.1 | policy_definitions.yaml + generate_policy.py | **DEFERRED — needs scoped design** | high regression risk on security-critical files; corpus + readiness already pin behavior |
| 3.2 | SHA-256 pin SOUL.md | **CORRECTED — already exists in better form** | references/soul-safety-manifest.yaml is anchor-based (prose grep) deliberately — SOUL.md is actively edited; hash pin would false-FAIL readiness |
| 4.1 | Landlock kernel API on WSL2 6.18 | **FABRICATED on this kernel** | `landlock_create_ruleset` → errno 42 (ENOPROTOOPT = not supported); /sys/kernel/security has no lsm file; rootless docker tooling absent |
| 4.2 | seccomp profile dropping ptrace/mount/kexec/bpf | **TRUE — FIXED** | run-sandbox.sh already had SECCOMP_PROFILE hook; added sandbox/hermes-seccomp.json (Docker default minus drops), verified ptrace blocked in-container |
| 4.3 | `.agentignore` hides operator-runbook from agent | **FABRICATED mechanism** | Hermes loads only .hermes.md / AGENTS.md / CLAUDE.md / .cursorrules (hermes-agent skill ref); `.agentignore` here is a repo-created secret-pattern file (~/.agentignore), not a Hermes context mechanism |
| 4.4 | pass/Vault + get_ephemeral_token MCP | **DEFERRED — architecture decision** | replaces documented .env-600 model; needs user decision, out of scope today |

## 2. Implemented in R-14 (safe, verified, reversible)

1. **hardline-check.sh**: rule 8 extended `(sh|bash|zsh|dash)`; new rule 8b blocks
   `find ... -exec <shell> -c` on ANY root; new rule 13 blocks docker
   `run|create|exec` bind-mounting host paths (`-v /`, `-v=/`, `--volume`,
   `--mount source=`) — named volumes and `docker ps` remain allowed.
2. **hardline-corpus-test.sh**: 40 → 53 cases (new BLOCK + ALLOW); ALL green.
3. **sandbox/hermes-seccomp.json**: Docker canonical default profile
   (moby/profiles, defaultAction ERRNO, 441 allowed under cap gates) with
   `ptrace mount umount umount2 bpf kexec_load kexec_file_load` REMOVED from
   allow entries + explicit deny entry. Strictly stricter than Docker default.
4. **run-sandbox.sh**: defaults SECCOMP_PROFILE to the repo profile when
   present; `SECCOMP_PROFILE=none` opts out. Verified: normal sandbox cmd OK,
   ptrace denied (errno 1) inside, opt-out works.
5. **Firecrawl**: `PORT=127.0.0.1:3002` (both duplicate lines in
   ~/src/firecrawl/.env; docker compose up -d api); verified
   `127.0.0.1:3002->3002/tcp` and HTTP 200 on loopback.
6. **approvals.deny**: +7 docker patterns (130 → 137) written as real YAML
   (backup: /tmp/config.yaml.bak); verified via `hermes config get`.

## 3. Rejected / deferred (with reasons)

- 1.1 docker-group removal: destructive host change; needs explicit approval.
  Mitigation landed instead: hardline rule 13 + 7 deny patterns close the
  `docker run -v /` escape vector while run-sandbox.sh keeps working.
- 1.3.2 ephemeral key: script as written breaks auth (one-sided rotation);
  needs dual-file rotation + stack restart + doc updates — not applied.
- 1.3.3 git history purge: dummy key is intentionally committed; force-push is
  deny-listed by this repo's own config; filter-repo not installed. Do not
  rewrite history for a documented non-secret.
- 2.2 trash.sh: env overrides are documented operator features; trash is a
  move (recoverable), TOCTOU already handled by unique-dst + re-canonicalize.
- 2.3 whole-agent bwrap: mount set as specced breaks the live agent (state.db,
  ~/agent, /tmp, docker socket). Requires a design pass, not a blind edit.
- 3.1 policy generator: legit goal; needs its own scoped design to avoid
  regressing security-critical generated files.
- 4.1 Landlock: kernel does not support it (ENOPROTOOPT). Nothing to integrate.
- 4.3 doc bifurcation: `.agentignore` is not a Hermes mechanism; the existing
  threat-pattern scanner already filters injected context files.
- 4.4 pass/Vault: architecture decision for the user; today's model (.env 600,
  redaction) is documented and readiness-checked.

## 4. Blueprint self-contradictions found

- 1.2 p3 asks to block `find ... -exec sh -c`; 2.1's own proposed pre-flight
  scan uses `find "$PWD_REAL" -type l -exec sh -c ...` — the scan would be
  blocked by the rule it asks for.
- 1.3.3 requires `git push --force*` after history rewrite, which this repo's
  approvals.deny (rule 4) and hardline rule 12 explicitly forbid.
- 4.1 assumes Landlock on a kernel that returns ENOPROTOOPT.

## 5. Residual risk (honest limits)

- Regex deny-lists remain incomplete by construction; hardline 13 covers the
  known `-v` forms and named-volume escape is not possible without a host
  path source. Kernel-level enforcement (Landlock) is unavailable on this
  kernel, so app-layer rules remain the primary defense.
- The approvals.deny docker patterns use fnmatch; they block the common
  literal forms. Exotic quoting (`docker run --volume=/etc:/e` variants) is
  covered by the hardline regex layer (rule 13) which smart_policy invokes.
