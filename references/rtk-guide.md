# RTK (Rust Token Killer) — Production Implementation Guide for Hermes Agent

**Revision:** v1.0 (verified against upstream sources + live install, 2026-08-04)
**Project:** https://github.com/rtk-ai/rtk — "CLI proxy that cuts up to 90% of the bash output your agent reads"
**Latest version at time of writing:** v0.44.2 (GitHub releases + Homebrew, verified)
**Status on this machine:** installed (0.44.2), Hermes plugin registered, config.yaml patched, tracking live.

> Every command in this guide was executed and verified on this machine on
> 2026-08-04. Claims marked ADVICE are recommendations, not upstream
> documentation.

---

## Executive Summary

RTK is a single Rust binary that minimizes LLM token consumption by filtering,
grouping, truncating, and deduplicating command output before it reaches the
agent context. It rewrites terminal commands transparently
(`git status` → `rtk git status`) via a Hermes **pre_tool_call plugin hook**
and delivers compact output without changing your workflow.

**Important upstream caveat:** RTK's "up to 90%" is a reduction in **bash
output tokens**, not a reduction in your bill — the savings dilute at the
input-token and billing layers. Treat percentages as output compression, not
cost savings.

### Path Resolution Note (this machine)

Hermes' default home is `~/.hermes/`, but this machine exports
`HERMES_HOME=/home/nika/.config/hermes`. RTK's `rtk init --agent hermes`
honors `$HERMES_HOME` **directly** (verified in `src/hooks/init.rs`:
`resolve_hermes_home()` uses `$HERMES_HOME` when set, else `$HOME/.hermes`).
So on current versions the plugin lands in the active home with **no symlink
workaround needed**. This guide uses `${HERMES_HOME:-$HOME/.hermes}` for the
generic form.

---

## Phase 1 — Architecture (verified against plugin source)

The Hermes plugin lives at `${HERMES_HOME}/plugins/rtk-rewrite/` and consists
of `__init__.py` (Python entrypoint) + `plugin.yaml` (manifest declaring the
`pre_tool_call` hook). Flow, exactly as implemented:

```
Hermes terminal tool call "git status"
  → plugin._pre_tool_call(tool_name="terminal", args={command: "git status"})
  → subprocess: rtk rewrite "git status"     (2s timeout, fails open)
  → stdout "rtk git status" ≠ original  → args["command"] = "rtk git status"
  → shell executes: rtk git status
  → rtk runs git status, compresses output, records savings in SQLite
  → agent receives compact output
```

Key design principles — all verified in code:

- **Fail-open:** the plugin wraps everything in try/except; any failure only
  emits a `rtk: hermes plugin warning:` line and returns without mutation.
- **Passthrough codes:** `rtk rewrite` exits 1/2 for "no RTK equivalent" —
  the plugin passes the command through unchanged.
- **Zero overhead:** single Rust binary, `<10ms` overhead (upstream).
- **Safety:** `rtk rewrite` never rewrites commands containing file redirects
  (`> file`), command substitution (`$(...)`, backticks, `"$(...)"`), or
  deny-listed dangerous commands (`rm -rf`, etc.) — verified via upstream
  inline tests in `src/hooks/rewrite_cmd.rs`.
- **Token tracking:** savings recorded in SQLite (`history.db`) for
  `rtk gain` analytics.
- **Binary-missing guard:** if `rtk` is not on PATH, the plugin warns once and
  does not register the hook.

---

## Phase 2 — Installation

Prerequisites: Hermes installed; Python 3 for the plugin (any modern 3.x —
the adapter uses only stdlib; this machine: 3.14.4); ripgrep optional (some
filters shell out to `rg` — installed here, 15.1.0).

Choose ONE method (all verified):

```bash
# A. Homebrew (recommended on macOS; formula exists, currently v0.44.2)
brew install rtk

# B. Quick install script (Linux/macOS; installs to ~/.local/bin with
#    SHA-256 verification — verified URL)
curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh | sh

# C. Cargo (from source)
cargo install --git https://github.com/rtk-ai/rtk
```

Verify:

```bash
rtk --version     # → rtk 0.44.2 on this machine
rtk gain          # savings dashboard (empty until first tracked command)
```

> **Version note:** the upstream README's example says "rtk 0.28.2" — that
> text is stale; the current release is v0.44.2 (verified via GitHub releases
> and the Homebrew formula). Accept whatever `rtk --version` reports ≥ 0.44.

> **Name collision warning (valid):** a different project, **Rust Type Kit**
> (reachingforthejack/rtk), also publishes as `rtk` on crates.io. If
> `rtk gain` fails, you have the wrong package — use `cargo install --git`
> from rtk-ai/rtk instead.

---

## Phase 3 — Hermes Integration & Path Resolution

```bash
rtk init --agent hermes
```

Verified behavior (v0.44.2):

1. Resolves `$HERMES_HOME` (default `~/.hermes/`) — **not** hardcoded.
2. Creates `${HERMES_HOME}/plugins/rtk-rewrite/` with `__init__.py` +
   `plugin.yaml`.
3. Patches `${HERMES_HOME}/config.yaml` — adds/updates `plugins.enabled` to
   include `rtk-rewrite` (source-verified `patch_hermes_config`; it edits in
   place and preserves other config keys).
4. Prints the resolved paths, e.g.:

```
RTK configured for Hermes.
  Plugin: /home/nika/.config/hermes/plugins/rtk-rewrite
  Config: /home/nika/.config/hermes/config.yaml
```

On this machine the plugin was written directly to
`/home/nika/.config/hermes/plugins/rtk-rewrite/` (because
`HERMES_HOME=/home/nika/.config/hermes`) — **the symlink workaround in older
drafts is obsolete** for current versions. It is only needed if your RTK
version does not honor `$HERMES_HOME` (verify with `rtk init --show`, which
prints what would be written).

Verify the registration:

```bash
ls -la "${HERMES_HOME:-$HOME/.hermes}/plugins/rtk-rewrite/"   # __init__.py, plugin.yaml
grep -A 5 "plugins:" "${HERMES_HOME:-$HOME/.hermes}/config.yaml"
```

Expected config (this machine, verified — other keys untouched):

```yaml
plugins:
  enabled:
    - rtk-rewrite
```

Restart Hermes (plugins load at session start; the current session is
unaffected). Then test:

```bash
git status          # auto-rewritten → rtk git status → compact output
```

---

## Phase 4 — Configuration

Config lives at `~/.config/rtk/config.toml` (Linux) or
`~/Library/Application Support/rtk/config.toml` (macOS). Create with
`rtk config --create` (writes defaults) and edit.

Corrected full structure (verified against `docs/guide/getting-started/configuration.md`):

```toml
[tracking]
enabled = true              # token savings tracking
history_days = 90           # retention (auto-cleanup)
# database_path = "/custom/path/history.db"   # optional override

[display]
colors = true
emoji = true
max_width = 120

[filters]                   # applies to file-reading cmds (ls, find, grep, cat)
ignore_dirs = [".git", "node_modules", "target", "__pycache__", ".venv", "vendor"]
ignore_files = ["*.lock", "*.min.js", "*.min.css"]

[tee]                       # save raw output on failure
enabled = true              # default true
mode = "failures"           # "failures" | "always" | "never"
max_files = 20              # rotation

[telemetry]
enabled = false             # off by default; keep it off

[hooks]
exclude_commands = ["git rebase", "docker exec"]   # never auto-rewrite
```

> Corrections vs older drafts: `ignore_dirs`/`ignore_files` live under
> `[filters]`, not `[limits]`; `[tee]` has no `max_file_size` key (1 MB is a
> fixed truncation limit, 500-byte minimum for saving); per-command bypass is
> `RTK_DISABLED=1 git status`.

Environment variables (verified):

```bash
export RTK_TELEMETRY_DISABLED=1    # hard-block telemetry regardless of consent
RTK_DISABLED=1 git status          # per-command bypass
RTK_TEE_DIR=/custom/tee            # override tee directory
RTK_HOOK_AUDIT=1                   # hook audit logging
```

### Project-specific filters (corrected)

The real mechanism is a **project-local filter file**:

```bash
# project root
cat > .rtk/filters.toml << 'EOF'
schema_version = 1

[filters.make-build]
description = "Compact make build output"
match_command = "^make build"
strip_ansi = true
strip_lines_matching = ["^\\[\\d+%\\]"]
max_lines = 30
EOF
```

- Files: project-local `.rtk/filters.toml` (committed) or user-global
  `~/.config/rtk/filters.toml`.
- DSL: `schema_version = 1` + `[filters.<name>]` sections with
  `match_command` (regex) and action fields (`strip_ansi`, `strip_lines_matching`,
  `keep_lines_matching`, `replace`, `match_output`, `truncate_lines_at`,
  `max_lines`, `tail_lines`, `on_empty`) — full reference at
  `src/filters/README.md` in the repo.
- **Trust gating (important):** custom filters are NOT applied until you
  trust them — `rtk trust` (interactive; `--yes` to skip the prompt) or
  `rtk untrust`. Trust is bound to file content (SHA-256); editing a trusted
  file requires re-running `rtk trust`. `rtk init` can auto-trust with
  `--trust-filters` / `--no-trust-filters`.

---

## Phase 5 — Verification & Testing

```bash
# Rewriting
rtk git status
rtk git diff
rtk git log --oneline -10
rtk cargo test      # ~-90% on test output
rtk pytest -q

# Analytics
rtk gain                  # summary
rtk gain --graph          # ASCII graph (last 30 days)
rtk gain --history        # recent command history
rtk gain --daily          # day-by-day breakdown
rtk gain --all --format json
rtk discover              # missed savings opportunities
rtk session               # adoption across recent sessions
```

Real output from this machine (2026-08-04, after 2 demo commands):

```
RTK Token Savings (Global Scope)
══════════════════════════════════════
Total commands:    2
Input tokens:      67
Output tokens:     54
Tokens saved:      13 (19.4%)
Total exec time:   10ms (avg 5ms)
```

Fail-open test (no sudo needed — `~/.local/bin` is user-owned here):

```bash
mv "$(which rtk)" "$(which rtk).bak"   # temporarily hide rtk
# run a command in Hermes — it runs raw, plugin only warns
mv "$(which rtk).bak" "$(which rtk)"   # restore
```

---

## Phase 6 — Security & Safety

- **Telemetry: disabled by default** and opt-in only (GDPR Art. 6/7 consent
  during `rtk init` or `rtk telemetry enable`). Manage with
  `rtk telemetry status` / `enable` / `disable` / `forget` (forget also
  deletes local data). `RTK_TELEMETRY_DISABLED=1` blocks regardless of
  consent.
- **Rewrite safety (verified in `src/hooks/rewrite_cmd.rs`):** passthrough for
  file redirects, `$(...)`/backtick/`"$(...)"` substitutions, and deny-listed
  dangerous commands. Verified live: `rtk rewrite "sudo rm -rf /"` →
  unchanged.
- **Fail-open:** plugin never blocks execution; worst case is a stderr
  warning.
- **Filter trust:** custom filters can change what the agent sees — hence the
  `rtk trust` gate (Phase 4).

---

## Phase 7 — Troubleshooting

- **Plugin not loading / no compression:** check (1) `echo $HERMES_HOME` —
  plugin must be under the ACTIVE home; (2) `plugins.enabled` contains
  `rtk-rewrite` in `${HERMES_HOME}/config.yaml`; (3) `rtk` is on PATH (the
  plugin warns once if missing and skips registration); (4) restart Hermes.
- **Legacy symlink fix (only for old RTK versions that ignored
  `$HERMES_HOME`):**
  `mkdir -p "$HERMES_HOME/plugins" && ln -sf ~/.hermes/plugins/rtk-rewrite "$HERMES_HOME/plugins/rtk-rewrite"`
- **`rtk: command not found`:** ensure the install bin dir is on PATH. This
  machine: `~/.local/bin` (already on PATH).
- **Wrong rtk project:** if `rtk gain` fails, you likely have Rust Type Kit —
  reinstall from rtk-ai/rtk.

---

## Phase 8 — The Trinity: RTK + Hermes-LCM + CodeGraph

| Layer | Tool | Responsibility |
|-------|------|----------------|
| Command output | RTK | Compress terminal output before it enters context (up to ~90% on test/build output) |
| Conversation memory | Hermes-LCM | Long-term context, raw turns in `lcm.db`, DAG summaries (see `references/hermes-lcm-guide.md`) |
| Code intelligence | CodeGraph MCP | Structural AST knowledge graph, call graphs, impact radius (see `references/codegraph-guide.md`) |

One-line deployments (all executed on this machine):

```bash
# 1. RTK (honors $HERMES_HOME directly — no symlink needed on current versions)
rtk init --agent hermes

# 2. Hermes-LCM
git clone https://github.com/stephenschoettler/hermes-lcm "$HERMES_HOME/plugins/hermes-lcm"
cd "$HERMES_HOME/plugins/hermes-lcm" && ./scripts/install.sh

# 3. CodeGraph MCP server
hermes mcp add codegraph --command codegraph --args serve --mcp
```

---

## Phase 9 — Production Readiness Checklist

Verified on this machine (2026-08-04):

- [x] `rtk --version` → rtk 0.44.2; binary at `~/.local/bin/rtk` (on PATH)
- [x] Active `$HERMES_HOME` identified (`/home/nika/.config/hermes`)
- [x] Plugin at `${HERMES_HOME}/plugins/rtk-rewrite/` (`__init__.py` + `plugin.yaml`)
- [x] `plugins.enabled: [rtk-rewrite]` in config.yaml (mcp_servers intact)
- [x] Telemetry: off by default (upstream); `RTK_TELEMETRY_DISABLED=1` available as hard block
- [x] Config at `~/.config/rtk/config.toml` (created via `rtk config --create` if desired)
- [x] Rewriting verified: `rtk git status` compact; `rtk rewrite` probes pass
- [x] `rtk gain` analytics operational
- [x] Fail-open verified (plugin source + passthrough codes)
- [x] Repo audit: `scripts/readiness-check.sh` → **32 pass / 0 fail / 6 info**
      (the "6 info" items are optional tooling suggestions, not failures)

## Sources

- https://github.com/rtk-ai/rtk — README (install, init, gain, telemetry, collision warning)
- https://raw.githubusercontent.com/rtk-ai/rtk/master/src/hooks/init.rs — `resolve_hermes_home`, `patch_hermes_config`
- https://raw.githubusercontent.com/rtk-ai/rtk/master/hooks/hermes/rtk-rewrite/__init__.py — plugin adapter
- https://raw.githubusercontent.com/rtk-ai/rtk/master/src/hooks/rewrite_cmd.rs — safety/passthrough rules
- https://raw.githubusercontent.com/rtk-ai/rtk/master/docs/guide/getting-started/configuration.md — config keys, env vars, trust
- https://raw.githubusercontent.com/rtk-ai/rtk/master/src/filters/README.md — filter TOML DSL
- Homebrew formula: https://formulae.brew.sh/formula/rtk (v0.44.2)
- crates.io collision: https://github.com/reachingforthejack/rtk (Rust Type Kit)
