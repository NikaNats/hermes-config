# Hermes LCM (hermes-lcm) — Production Installation & Operations Guide

**Revision:** v2.0 (corrected & verified against primary sources, 2026-08-04)
**Project:** https://github.com/stephenschoettler/hermes-lcm (Lossless Context Management plugin for Hermes Agent)
**RTK:** https://github.com/rtk-ai/rtk (Rust Token Killer, CLI proxy)
**Plugin version covered:** v0.21.0-rc1 line (15 tools, core schema v5)

> Every path, command, and default in this guide was checked against the
> project README, docs/operator-guide.md, docs/features-overview.md, the
> v0.21.0-rc1 release notes, and the official rtk README on 2026-08-04.
> Anything advisory (not upstream-documented) is explicitly marked ADVICE.

---

## 0. Scope, environment notes, and what changed in v2.0

### 0.1 The HERMES_HOME question (most important)

- **Canonical default home for Hermes Agent is `~/.hermes/`.** The hermes-lcm
  README and all upstream examples use `~/.hermes/plugins/hermes-lcm`.
- **`HERMES_HOME` overrides the home.** When the env var is set (e.g. this
  machine: `HERMES_HOME=/home/nika/.config/hermes`), every Hermes path —
  config, skills, plugins, `lcm.db` — resolves under `$HERMES_HOME`, not
  `~/.hermes`.
- **Rule:** never hardcode `~/.hermes` in scripts; resolve from `$HERMES_HOME`
  (`${HERMES_HOME:-$HOME/.hermes}`). The rest of this guide writes
  `~/.hermes/...` because that is upstream's canonical form — substitute your
  `$HERMES_HOME` if you have set one.

Example for this machine:

```bash
# Generic (default install):
PLUGIN_DIR=~/.hermes/plugins/hermes-lcm

# If HERMES_HOME is set (like this machine: /home/nika/.config/hermes):
PLUGIN_DIR="$HERMES_HOME/plugins/hermes-lcm"
```

### 0.2 Corrections applied vs. the previous revision (v1)

1. **Folder location:** canonical install path is now `~/.hermes/plugins/`
   (with the `HERMES_HOME` note above). Previous revision used
   `~/.config/hermes/`, which is only correct when `HERMES_HOME` points there.
2. **RTK integration:** replaced with the official `rtk init --agent hermes`
   command (verified in rtk-ai/rtk README), plus the manual pip fallback from
   the rtk-hermes plugin README.
3. **Tool coverage:** full 15-tool inventory added (was 5 core tools), with the
   v0.21.0-rc1 "Advanced / Evidence" tools documented in Phase 4.
4. **Database location:** documented `LCM_DATABASE_PATH` default resolution
   (`$HERMES_HOME/lcm.db`) and override.
5. **Upgrade details:** v0.21.0-rc1 core schema stays v5, additive named
   migrations, no manual migration/backfill — **with one important correction:
   the new feature stores do NOT auto-activate on restart; they are opt-in**
   (see 9.3).

### 0.3 Prerequisites

- Hermes Agent (any modern release; LCM works from Hermes v0.16+ via the
  context-engine path)
- Python 3.11+
- No required third-party runtime dependencies
  - `tiktoken` (optional) — token estimates; character-based fallback otherwise
  - `regex` (optional) — timeout support for message-ignore patterns
  - embeddings (optional) — semantic recall; `lcm_recall` works FTS-only without
    them (`docs/embeddings-setup.md`)

---

## Phase 1 — Install the plugin

Canonical install path: clone `hermes-lcm` as a general user plugin.

```bash
git clone https://github.com/stephenschoettler/hermes-lcm \
  ~/.hermes/plugins/hermes-lcm
```

Profile-specific install:

```bash
git clone https://github.com/stephenschoettler/hermes-lcm \
  ~/.hermes/profiles/myprofile/plugins/hermes-lcm
```

**`scripts/install.sh` is still required** — it links the bundled `hermes-lcm`
skill into the matching global/profile `skills/` directory so the plugin's
recall policy and references appear in ordinary skill discovery. Run it even
when the checkout already lives at the canonical plugin path (it leaves the
checkout in place and preflights both paths before creating links):

```bash
cd ~/.hermes/plugins/hermes-lcm
./scripts/install.sh

# Optional profile-aware install:
HERMES_PROFILE=myprofile ./scripts/install.sh
```

---

## Phase 2 — Activate and verify

The plugin has **two names** — both must be configured:

- plugin manifest name: `hermes-lcm`
- runtime context-engine name: `lcm`

Add to `config.yaml` (path: `$HERMES_HOME/config.yaml`, i.e.
`~/.hermes/config.yaml` by default):

```yaml
plugins:
  enabled:
    - hermes-lcm

context:
  engine: lcm
```

Restart Hermes after changing plugin or context-engine config.

Verify:

```bash
hermes plugins
```

Expected signals:

- plugin list includes `hermes-lcm`
- selected context engine is `lcm`
- tool list includes all 15 schemas (see Phase 4 for the full table)
- ordinary skill discovery includes `hermes-lcm`

Typical output:

```text
Plugins (1):
  ✓ hermes-lcm v0.21.0-rc1 (15 tools)

Provider Plugins:
  Context Engine: lcm
```

For source checkouts, `lcm_status`, `/lcm status`, `lcm_inspect`, `lcm_doctor`,
and `/lcm doctor` also report the loaded plugin path and git identity
(`plugin_git_commit`, `plugin_git_branch`, `plugin_git_dirty`).

> If startup logs mention `context-engine schemas` or a `Path B fallback`, that
> is expected on older hosts (e.g. Hermes Agent v0.16): all 15 `lcm_*` tools
> remain available through the context-engine path.

---

## Phase 3 — Core configuration and security/redaction

Most installs only need `plugins.enabled` and `context.engine: lcm`. The knobs
below are environment variables read at startup (place them in the Hermes env
or your shell profile).

### 3.1 Common tuning

| Variable | Default | Use |
|----------|---------|-----|
| `LCM_CONTEXT_THRESHOLD` | `0.35` | Fraction of context window that triggers LCM compaction |
| `LCM_FRESH_TAIL_COUNT` | `32` | Recent messages protected from compaction |
| `LCM_FRESH_TAIL_MAX_TOKENS` | `0` | Token cap for the protected fresh tail (`0` disables; newest message and complete assistant/tool-result groups always retained) |
| `LCM_INCREMENTAL_MAX_DEPTH` | `3` | Max DAG condensation depth (`-1` unlimited, `0` leaf only); enables hierarchical summarization |
| `LCM_LEAF_CHUNK_TOKENS` | `20000` | Raw-backlog floor before leaf compaction |
| `LCM_DYNAMIC_LEAF_CHUNK_ENABLED` | `false` | Chunk-sized leaf compaction passes instead of one full pass |
| `LCM_NEW_SESSION_RETAIN_DEPTH` | `2` | DAG depth retained after manual `/new` |

**Threshold ownership:** when `context.engine: lcm` is active,
`LCM_CONTEXT_THRESHOLD` is the compaction threshold LCM uses. Hermes core
`compression.threshold` belongs to the built-in compressor, and core
`compression.enabled` remains the global gate — **leave it enabled when using
LCM**.

### 3.2 Sensitive-pattern redaction (security)

Redaction is **disabled by default** so ordinary LCM storage and `lcm_expand`
stay lossless. Opt in only when you need it:

```bash
export LCM_SENSITIVE_PATTERNS_ENABLED=true
# default catalog: api_key,bearer_token,password_assignment,private_key
export LCM_SENSITIVE_PATTERNS=api_key,bearer_token,password_assignment,private_key
```

Behavior (verified in README + operator guide):

- Matched secret values are replaced with metadata-only placeholders **before**
  SQLite, FTS, summaries, active replay, and externalized payload JSON receive
  the content.
- **Intentionally not lossless:** the raw matched secret is unrecoverable after
  redaction. `password_assignment` placeholders omit the digest; other
  categories include a short truncated SHA-256 digest for correlation.
- **Forward-only:** enabling it does NOT rewrite existing rows, FTS shadow
  tables, summaries, or externalized payloads written before the setting.
- Catalog entries: `api_key` (api_key/api_token/access_token/secret_key/
  client_secret assignments or JSON keys), `bearer_token` (`Bearer ...` and
  token-like JSON keys), `password_assignment` (password/passwd/pwd/passphrase
  assignments or JSON keys, incl. quoted values with spaces), `private_key`
  (PEM private-key blocks).
- `lcm_status`, `lcm_inspect`, and `lcm_doctor` report the enabled state and
  configured pattern names without exposing raw values.

### 3.3 Model and timeout settings (summary/expansion)

| Variable | Default | Use |
|----------|---------|-----|
| `LCM_SUMMARY_MODEL` | auxiliary | Override summarization model |
| `LCM_SUMMARY_FALLBACK_MODELS` | empty | Models tried after the primary fails |
| `LCM_SUMMARY_CIRCUIT_BREAKER_FAILURE_THRESHOLD` | `2` | Failures before a route is skipped temporarily |
| `LCM_SUMMARY_CIRCUIT_BREAKER_COOLDOWN_SECONDS` | `300` | Cooldown for an open summary route |
| `LCM_SUMMARY_TIMEOUT_MS` | `60000` | Timeout for one summarization call |
| `LCM_EXPANSION_MODEL` | summary/aux | Override `lcm_expand_query` synthesis model |
| `LCM_EXPANSION_CONTEXT_TOKENS` | `32000` | Context budget for `lcm_expand_query` |
| `LCM_EXPANSION_TIMEOUT_MS` | `120000` | Timeout for one expansion call |

---

## Phase 4 — Noise filtering and the full 15-tool inventory

### 4.1 Noise filtering (what LCM stores)

| Variable | Default | Use |
|----------|---------|-----|
| `LCM_IGNORE_SESSION_PATTERNS` | empty | Comma-separated session globs **excluded** from LCM storage |
| `LCM_STATELESS_SESSION_PATTERNS` | empty | Comma-separated session globs kept **read-only** |
| `LCM_IGNORE_MESSAGE_PATTERNS` | empty | Comma-separated regex patterns; matching message content excluded from LCM storage |
| `LCM_EMPTY_LIFECYCLE_GC_ENABLED` | `true` | Automatic pruning of lifecycle rows for sessions that never ingested anything |
| `LCM_EMPTY_LIFECYCLE_GC_THRESHOLD` | `200` | Lifecycle-row count at which the GC pass fires |
| `LCM_EMPTY_LIFECYCLE_GC_MAX_AGE_HOURS` | `24` | GC only deletes empty lifecycle rows at least this old (`0` only in trusted/test envs) |

Operator commands (opt-in surface; enable with `export LCM_ENABLE_SLASH_COMMAND=1`):

- `/lcm doctor clean` — read-only scan for obvious junk/noise session candidates
- `/lcm doctor clean apply` — backup-first cleanup; requires
  `LCM_DOCTOR_CLEAN_APPLY_ENABLED=true`
- `/lcm rotate` / `/lcm rotate apply` — in-place compact of the active session
  **without changing `session_id`**: preserves the live tail, advances the
  lifecycle frontier past pre-tail raw messages, writes a rolling
  `*-rotate-latest.sqlite3` backup. Raw messages stay recoverable via
  `lcm_load_session` / `lcm_expand`.
- `/lcm backup` — timestamped SQLite backup
- `/lcm doctor` — read-only SQLite/FTS repair diagnostics
- `/lcm doctor source` — read-only scan for legacy blank-source rows

**Policy:** start with diagnostics before any cleanup; every apply path is
narrow and backup-first.

### 4.2 The 15 tools (complete list)

| # | Tool | Use |
|---|------|-----|
| 1 | `lcm_grep` | Search current-session raw messages and summaries; opt-in externalized payload search and raw-message archive recovery |
| 2 | `lcm_recall` | Cross-conversation, all-time semantic search (RRF fusion of full-text + summary/chunk vectors); FTS-only without embeddings |
| 3 | `lcm_query_state` | Query the **opt-in V4 assertion sidecar** for bounded current/historical facts, preferences, recommendations, commitments, actions, status; every result carries an exact message ref/span/quote; conflicts stay visible |
| 4 | `lcm_compute` | Date/distinct-count/sum/difference/ordering/latest-state operations over exact cited evidence; ambiguous or incomplete inputs fail closed |
| 5 | `lcm_compile_evidence` | Validate one bounded provider-neutral semantic proposal against exact stored refs; returns an evidence brief with explicit sufficiency state, never final prose |
| 6 | `lcm_evidence_pack` | Hydrate and validate bounded baseline exact refs in the same `lcm.db`; repair unique in-window quote spans; optional immutable canonical computation trace |
| 7 | `lcm_retrieve` | Opt-in bounded controller for one continuous answerer turn: typed evidence slots, ≤3 targeted calls to existing retrieval tools, exact observed refs only, can finish through `lcm_compute` |
| 8 | `lcm_recent` | Recent summaries by natural UTC period (rollups preferred, bounded leaf fallback) |
| 9 | `lcm_load_session` | Load one ordered raw-message transcript page for an explicit `session_id`; paginate with `after_store_id`/`next_cursor` |
| 10 | `lcm_describe` | Inspect the current-session DAG or preview an `externalized_ref` without loading full content |
| 11 | `lcm_expand` | Recover source messages, child summaries, or externalized payloads with pagination |
| 12 | `lcm_expand_query` | Answer a question using expanded current-session LCM context with a bounded answer |
| 13 | `lcm_status` | Runtime health, context pressure, config, source lineage, lifecycle stats |
| 14 | `lcm_inspect` | **Read-only operator inventory**: current-session lineage, frontier/fresh-tail metadata, externalized refs, compaction skip/no-op reasons, matched ignore/stateless patterns. Metadata only — use retrieval tools for content |
| 15 | `lcm_doctor` | Database, FTS, lifecycle, config, and context-pressure diagnostics |

**Which are "Advanced / Evidence" (v0.21.0-rc1):** `lcm_query_state`,
`lcm_compute`, `lcm_compile_evidence`, `lcm_evidence_pack`, and `lcm_retrieve`
are the five new query/evidence tool schemas added in the RC line. They are
extremely useful in production (coding, research, audit) — **but their backing
stores are opt-in** (see 9.3). `lcm_inspect` is one of the ten base tools
(operator/diagnostics trio with `lcm_status` and `lcm_doctor`), not new in
v0.21 — it is still worth spotlighting as a read-only lineage/metadata
inventory.

---

## Phase 5 — Database location and backups

### 5.1 Default location

- **Default:** `LCM_DATABASE_PATH` resolves to **`$HERMES_HOME/lcm.db`** —
  i.e. `~/.hermes/lcm.db` on a default install (unset `HERMES_HOME`).
- On this machine (`HERMES_HOME=/home/nika/.config/hermes`), that means
  `~/.config/hermes/lcm.db` unless overridden.

### 5.2 Moving the database (backup/sync)

```bash
export LCM_DATABASE_PATH=/path/to/custom/lcm.db
```

Upstream suggests a profile-scoped path such as `~/.hermes/hermes-lcm.db`.
Move an existing database only while Hermes (and every writer) is stopped;
copy `lcm.db` together with any `lcm.db-wal` and `lcm.db-shm` companions as one
quiescent snapshot.

### 5.3 Backups

- **Online backup:** `/lcm backup` (with `LCM_ENABLE_SLASH_COMMAND=1`) — the
  only supported online backup path while Hermes or another writer may be
  running.
- **Offline backup:** stop all writers, then copy `lcm.db` (+ `-wal`/`-shm`)
  together.
- `/lcm rotate apply` writes a rolling `*-rotate-latest.sqlite3` under the same
  backup directory as `/lcm backup` (bounded disk usage across repeats).

---

## Phase 6 — Maintenance and upgrade

### 6.1 Updating the plugin

Cloned directly into the plugin directory:

```bash
cd ~/.hermes/plugins/hermes-lcm && git pull --ff-only
```

Profile-specific clone:

```bash
cd ~/.hermes/profiles/myprofile/plugins/hermes-lcm && git pull --ff-only
```

Symlink install from a separate checkout:

```bash
./scripts/update.sh
```

Restart Hermes after updating.

### 6.2 Upgrading to v0.21.0-rc1 (verified upgrade path)

1. While the old runtime is running, run `/lcm backup`. (If Hermes or any
   other SQLite writer may still be running, this is the only supported online
   backup path.)
2. Alternative: stop every writer, then copy the profile's `lcm.db` plus any
   `lcm.db-wal`/`lcm.db-shm` companions together as one quiescent snapshot.
3. Update the checkout to the RC and restart Hermes.
4. Send one normal message, then confirm `lcm_status` reports plugin version
   `0.21.0-rc1` and the expected database path.
5. Migration-shape audit:
   `SELECT value FROM metadata WHERE key = 'schema_version';` → expected `5`.

### 6.3 What does and does NOT change (correction to a common belief)

- **Core schema stays version 5.** The v0.21.0-rc1 release notes state:
  "Keeps the core SQLite schema at version 5. New feature stores use additive
  named migrations in the same profile database; existing v0.20 databases need
  no manual migration or embedding backfill."
- **No manual database migration, data import, or content deletion is
  required** to upgrade. An existing v0.20 database opens in place on schema
  v5; a stock/default-off upgrade creates none of the new optional tables.
- **Important nuance:** the new functionality does **not** simply "activate
  after a restart". The five new tool *schemas* are visible in the tool list on
  stock installs, but automatic extraction, pre-answer evidence, assertion
  storage, query-view storage, and adaptive retrieval **remain off until you
  opt in** (flags below). A stock upgrade therefore changes no stored data.
- **Downgrade path:** if you later enable a 0.21-only store, treat the
  pre-upgrade backup as the downgrade path — do not open that modified database
  with an older plugin.

### 6.4 Opt-in flags for the evidence/query features

| Variable | Default | Effect |
|----------|---------|--------|
| `LCM_ASSERTIONS_ENABLED` | `false` | Create and bind the same-DB assertion sidecar so `lcm_query_state` can return typed, source-cited state (no extraction by itself) |
| `LCM_ASSERTION_EXTRACTION_ENABLED` | `false` | With assertions enabled, run bounded structured extraction over exact persisted rows before compaction (may send source text to the configured model) |
| `LCM_ASSERTION_EXTRACTION_MODEL` | empty | Extraction-model override (falls back to `LCM_EXTRACTION_MODEL`, then summary model) |
| `LCM_QUERY_VIEWS_ENABLED` | `false` | Create and bind demand-shaped evidence views (no model/retrieval provider invoked) |
| `LCM_ADAPTIVE_RETRIEVAL_ENABLED` | `false` | Enable `lcm_retrieve` and bind query views for evidence reuse |
| `LCM_PREANSWER_EVIDENCE_ENABLED` | `false` | Enable the automatic pre-answer evidence hook |
| `LCM_PREANSWER_EVIDENCE_MODE` | empty | `off`, `legacy_selective`, or `requirements_v1` |
| `LCM_SELECTIVE_COMPILER_ENABLED` | `false` | Semantic selector for code-derived closed operations |

Read `docs/operator-guide.md#upgrade-from-v0200-to-v0210-rc1` before enabling
any of these.

### 6.5 Other useful switches

| Variable | Default | Effect |
|----------|---------|--------|
| `LCM_LARGE_OUTPUT_EXTERNALIZATION_ENABLED` | `false` | Store oversized tool results/media/raw payloads in plugin-managed JSON files |
| `LCM_LARGE_OUTPUT_EXTERNALIZATION_THRESHOLD_CHARS` | `12000` | Externalization threshold |
| `LCM_LARGE_OUTPUT_ACTIVE_REPLAY_STUBBING_ENABLED` | `false` | Replace token-heavy tool results with recoverable refs in active replay (requires externalization) |
| `LCM_TEMPORAL_ROLLUPS_ENABLED` | `false` | Derived UTC day/week/month summary rollups |
| `LCM_EMBEDDINGS_ENABLED` | `false` | Embedding warmup/backfill and semantic retrieval storage |
| `LCM_PROACTIVE_RECALL_ENABLED` | `false` | Budget-capped "relevant memories" injection at assembly (needs embeddings) |
| `LCM_FTS_INTEGRITY_CHECK_INTERVAL_HOURS` | `24` | FTS5 deep integrity-check cadence |
| `LCM_ENABLE_SLASH_COMMAND` | `false` | Enable the `/lcm` operator command surface |

For large existing databases with historical tool rows, upstream ships
`scripts/backfill_externalized_tool_outputs.py` to pre-create native recovery
sidecars (manifest-based rollback; see `docs/operator-guide.md`).

---

## Pro-Tip — RTK (Rust Token Killer) integration

RTK is a CLI proxy that reduces LLM token consumption by 60–90% on common dev
commands by compacting command output (smart filtering, grouping, truncation,
deduplication). Integrated with Hermes, terminal commands are transparently
rewritten to their RTK equivalents **before execution**, so the compact output
is what enters LCM's memory.

### Official one-shot setup

```bash
# 1. Install RTK (Linux/macOS quick install → ~/.local/bin)
curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh | sh
# or: brew install rtk

# 2. Install the Hermes plugin adapter (official command, verified in rtk README)
rtk init --agent hermes

# 3. Restart Hermes, then test
git status   # auto-rewritten to: rtk git status
```

`rtk init --agent hermes` is the documented Hermes entry in the official RTK
Quick Start (`rtk init -g` is the Claude Code/Copilot default; `--agent hermes`
selects Hermes). Hermes is a **plugin-based** agent: RTK uses the plugin API
(`pre_tool_call` hook) to rewrite commands before execution, rather than a
shell hook.

### Manual fallback (if you prefer explicit control)

Per the rtk-hermes plugin README (ogallotti/rtk-hermes, PyPI: `rtk-hermes`,
entry point `rtk-rewrite`):

```bash
# Install into the SAME Python env that runs hermes (not system Python!)
HERMES_PY="$HOME/.hermes/hermes-agent/venv/bin/python"
"$HERMES_PY" -m pip install --upgrade rtk-hermes

# If the venv has no pip, use uv (never --break-system-packages):
~/.local/bin/uv pip install --python "$HOME/.hermes/hermes-agent/venv/bin/python" --upgrade rtk-hermes
```

Then add to config.yaml and restart:

```yaml
plugins:
  enabled:
    - rtk-rewrite
```

> Caveat: `hermes plugins enable rtk-rewrite` may not recognize pip-only entry
> points; editing `plugins.enabled` directly is the reliable path.

Runtime behavior is env-controlled:

| Variable | Default | Behavior |
|----------|---------|----------|
| `RTK_HERMES_MODE` | `rewrite` | `rewrite` mutates commands; `suggest` logs suggestions only; `off` disables |
| `RTK_HERMES_TIMEOUT_MS` | `2000` | Max time in `rtk rewrite` per command |
| `RTK_HERMES_PREVIEW_MARKER` | `true` | Prefix rewritten commands with `: RTK &&` for clear previews |
| `RTK_HERMES_BACKENDS` | `local` | Backends where rewrites are allowed (`local,ssh` or `all` only if `rtk` is installed there too) |

**Security note (ADVICE):** RTK rewrites what the model *executes*; it does not
redact secrets from LCM storage. Keep `LCM_SENSITIVE_PATTERNS_ENABLED` as your
redaction layer — the two compose (RTK for output size, LCM redaction for
secrets).

---

## Appendix — Quick reference

**Core config:**

```yaml
plugins:
  enabled:
    - hermes-lcm
    # - rtk-rewrite      # optional RTK adapter
context:
  engine: lcm
```

**Environment variables you will most likely set in production:**

```bash
# Paths / database
export LCM_DATABASE_PATH="$HERMES_HOME/lcm.db"          # default; override to move it
# Compaction
export LCM_CONTEXT_THRESHOLD=0.35
export LCM_FRESH_TAIL_COUNT=32
# Noise filtering
export LCM_IGNORE_SESSION_PATTERNS=
export LCM_STATELESS_SESSION_PATTERNS=
export LCM_IGNORE_MESSAGE_PATTERNS=
# Security (opt-in)
export LCM_SENSITIVE_PATTERNS_ENABLED=true
export LCM_SENSITIVE_PATTERNS=api_key,bearer_token,password_assignment,private_key
# Evidence/query features (v0.21.0-rc1, opt-in)
export LCM_ASSERTIONS_ENABLED=false
export LCM_QUERY_VIEWS_ENABLED=false
export LCM_ADAPTIVE_RETRIEVAL_ENABLED=false
# Operators
export LCM_ENABLE_SLASH_COMMAND=1
```

**Sources**

- hermes-lcm README: https://github.com/stephenschoettler/hermes-lcm
- Operator guide: https://github.com/stephenschoettler/hermes-lcm/blob/main/docs/operator-guide.md
- Features overview: https://github.com/stephenschoettler/hermes-lcm/blob/main/docs/features-overview.md
- Retrieval tools reference: https://github.com/stephenschoettler/hermes-lcm/blob/main/docs/retrieval-tools.md
- v0.21.0-rc1 release notes: https://github.com/stephenschoettler/hermes-lcm/blob/main/.github/release-notes/v0.21.0-rc1.md
- RTK: https://github.com/rtk-ai/rtk
- rtk-hermes plugin: https://github.com/ogallotti/rtk-hermes
