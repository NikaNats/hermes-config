# CodeGraph + Hermes Agent: Complete Integration Guide

**Revision:** v1.0 (verified against live install + primary sources, 2026-08-04)
**Project:** https://github.com/colbymchenry/codegraph (local-first semantic code intelligence MCP server)
**npm package:** `@colbymchenry/codegraph` (latest at time of writing: 1.5.0)
**Status on this machine:** installed (1.5.0), registered in Hermes, `~/src/hermes-config` indexed, telemetry off.

> CodeGraph builds a local semantic graph of your code (symbols, callers,
> callees, routes, cross-language bridges) with a tree-sitter-based Rust kernel
> and stores it in SQLite (FTS5). The MCP server gives the agent precise,
> structural code context on demand — no blind Grep/Read loops.
>
> Every command below was executed and verified on this machine on 2026-08-04.
> Anything that is advisory (not upstream-documented) is marked ADVICE.

---

## Phase 1 — Install CodeGraph

Two install routes; pick one. **The old "Node.js >= 20.0.0 required" claim is
outdated** — the current README states "No Node.js required" (the curl route
ships a self-contained build with a bundled runtime) and the npm route "works
on any version".

### Route A: npm (global)

```bash
npm install -g @colbymchenry/codegraph
```

- Verify: `codegraph --version` (1.5.0 on this machine).
- On this machine npm's global prefix is `~/.local` and `~/.local/bin` is
  already on `PATH`, so the `codegraph` binary is immediately available.
- If your npm prefix bin dir is not on `PATH`, add it (see Troubleshooting).

### Route B: curl installer (self-contained, no Node needed)

```bash
curl -fsSL https://raw.githubusercontent.com/colbymchenry/codegraph/main/install.sh | sh
```

- Installs to `~/.local/bin`; works without Node (bundled runtime).

---

## Phase 2 — Register the MCP server in Hermes

Two native methods; no manual config-file editing required.

### Method A: Hermes native CLI (Recommended)

**Verified syntax** — note there is NO `--` separator; the stdio command is
passed with `--command`, and `--args` must be the LAST option:

```bash
hermes mcp add codegraph --command codegraph --args serve --mcp
```

> The form `hermes mcp add codegraph -- codegraph serve --mcp` does NOT work:
> it fails with `hermes: error: unrecognized arguments` (verified on this
> machine; nothing is written). The `--` double-dash is not a supported
> separator in `hermes mcp add`.

What happens (verified live):

1. Hermes spawns `codegraph serve --mcp` and connects.
2. It discovers the tool surface: `✓ Connected! Found 1 tool(s) ...` — see the
   tool-naming note below for why only one tool is listed by default.
3. It asks `Enable all 1 tools? [Y/n/select]` — answer `Y` (or `select` to
   pick a subset).
4. It writes the server to `$HERMES_HOME/config.yaml` under `mcp_servers`
   (this machine: `~/.config/hermes/config.yaml` — NOT `mcp.json`).

Resulting config (verified on this machine):

```yaml
mcp_servers:
  codegraph:
    command: codegraph
    args: [serve, --mcp]
    enabled: true
```

Optional Hermes-side knob for slow first launch (2-3s WASM grammar load):

```bash
hermes mcp add codegraph --command codegraph --connect-timeout 30 --args serve --mcp
```

> Order matters: `--connect-timeout` must come BEFORE `--args` (verified with
> the CLI parser). `--args` is `nargs=REMAINDER` — anything after it is passed
> verbatim to the stdio command, so
> `... --args serve --mcp --connect-timeout 30` sends `--connect-timeout 30`
> to `codegraph serve` instead of Hermes.

### Method B: CodeGraph's official multi-agent installer

```bash
codegraph install            # interactive; auto-detects installed agents
codegraph install --yes      # non-interactive
```

Verified facts about the installer:

- It detects and configures Claude Code, Cursor, Codex CLI, opencode, **Hermes
  Agent**, Gemini CLI, Antigravity IDE, and Kiro.
- For Hermes it writes the correct native format — `mcp_servers.codegraph`
  mapping to `codegraph serve --mcp` — under `$HERMES_HOME/config.yaml`
  (verified in the package's Hermes target: `dist/installer/targets/hermes.d.ts`).
- It adds a marker-fenced instruction block to agent instruction files using
  the exact markers `<!-- CODEGRAPH_START -->` ... `<!-- CODEGRAPH_END -->`
  (verified in package source). Hermes reads these via its AGENTS.md support.
- It wires up agents only — it does NOT index code. Indexing is Phase 3.
- Reversal: `codegraph uninstall` (strips agent config/markers; leaves
  `.codegraph/` indexes); `codegraph uninit` (removes a project index).

Restart Hermes after either method (MCP servers load at session start; there
is no hot-reload).

---

## Phase 3 — Index a project (required per project)

One-shot create + build (recommended, verified on this machine):

```bash
cd /path/to/your/project
codegraph init
```

Or, if `.codegraph/` already exists:

```bash
codegraph index [path]        # full re-index; --force to force, --quiet to reduce output
codegraph sync [path]         # incremental update (rarely needed manually — see auto-sync)
```

What happens (verified): a `.codegraph/` directory is created containing
`codegraph.db` (SQLite, FTS5 full-text search) and a self-ignoring
`.gitignore` so the index never pollutes git. Tree-sitter parses 20 languages;
edges capture calls/imports/extends/implements plus web-framework routes and
cross-language bridges (React Native, Expo, ObjC/Swift, etc.).

On this machine the demo index of `~/src/hermes-config` completed in ~180ms
(WAL journal, `node:sqlite` backend — no `database is locked` issues).

Remove a project index: `codegraph uninit`.

---

## Phase 4 — Verify the integration

```bash
hermes mcp list               # shows: codegraph  codegraph serve --mcp  all  ✓ enabled
hermes mcp test codegraph     # verified on this machine: Connected (333ms), 1 tool discovered
```

Start a NEW Hermes session, then ask: "What MCP tools do you have for code
analysis?" Expect:

- **Default surface = ONE tool:** `codegraph_explore` — the PRIMARY tool that
  answers "how does X work", "how does X reach Y", returns verbatim source
  grouped by file, call paths (including dynamic-dispatch hops grep can't
  follow), and a blast-radius summary.
- **Correction to many guides:** `codegraph_search`, `codegraph_node`,
  `codegraph_callers`, `codegraph_callees`, `codegraph_impact`,
  `codegraph_files`, and `codegraph_status` exist and are fully functional but
  are **unlisted by default** — everything they return already arrives inline
  on `codegraph_explore`. To expose any of them on the MCP surface, set
  `CODEGRAPH_MCP_TOOLS` in the server's environment, e.g.
  `CODEGRAPH_MCP_TOOLS=explore,node,search,callers`.
- **Hermes tool naming:** Hermes prefixes MCP tools, so on Hermes the tool is
  `mcp_codegraph_codegraph_explore` (server name `codegraph` + tool name).
  The CodeGraph-injected guidance says `codegraph_explore`; on Hermes the
  prefixed name is what the model sees in its tool list.
- Indexed projects are queryable via the `projectPath` argument even when the
  server's own working directory has no index.

---

## Pro-Tip: Hermes LCM + CodeGraph synergy

If you run the **Hermes-LCM** plugin (see `references/hermes-lcm-guide.md`),
the two compose cleanly:

1. LCM stores dialog history and compacts the active window long-term.
2. CodeGraph supplies precise, structural code context on demand, so LCM never
   has to absorb huge code blocks into the active window.

Workflow example:

> **You:** "Analyze the authentication flow in UserService and tell me where
> logs are written."
>
> **Hermes with CodeGraph:**
> 1. `mcp_codegraph_codegraph_explore "UserService auth flow"` — finds the
>    symbol and its call paths.
> 2. Reads only the relevant function source (returned inline with line
>    numbers).
> 3. Skips folder-wide grep/read budget burn.
> 4. LCM stores only the short structured result in history.

---

## Troubleshooting (corrected and verified)

- **`codegraph` command not found:** ensure the npm global bin dir is on
  `PATH`. This machine: `npm config get prefix` → `~/.local`, bin at
  `~/.local/bin` (already on `PATH`). The curl route installs to
  `~/.local/bin` too.
- **MCP connection timeout:** the Hermes-side knob is
  `hermes mcp add ... --connect-timeout N` (place it BEFORE `--args`; or use
  `connect_timeout` in the server config; defaults: connect 60s, tool-call
  120s). CodeGraph's first
  launch can take 2-3s loading WASM grammars; its own handshake timeout is
  tunable via `CODEGRAPH_STARTUP_HANDSHAKE_TIMEOUT_MS` (`0` disables). The
  `--path` flag on `codegraph serve` is real (binds the server to a specific
  project) but it exists for project binding, not timeout tuning.
- **Index stale after edits:** normally unnecessary — the MCP server auto-syncs
  via an OS file-event watcher (2-second debounce, source files only) and does
  a connect-time catch-up reconciliation on (re)connect. Manual sync
  (`codegraph sync`) is only for when the watcher is disabled (sandboxed
  environments, `CODEGRAPH_NO_DAEMON=1`) or when scripting against the index.
  **It is not git-hook based** — the auto-sync is a file watcher, not a
  post-commit hook.
- **WSL2 / Windows drive projects (`/mnt/c`, `/mnt/d`):** CodeGraph docs
  report `Transport closed` errors and WAL problems on Windows drives. Index
  projects on the Linux-native filesystem (e.g. under `~/`). If you must use
  `/mnt`, set `CODEGRAPH_NO_DAEMON=1` in the server env so each session runs
  in its own process. For a checkout shared between Windows and WSL, give each
  side its own index (`CODEGRAPH_DIR=.codegraph-win` on Windows).
- **Privacy:** CodeGraph collects anonymous usage stats by default. Disable
  with `codegraph telemetry off` or `CODEGRAPH_TELEMETRY=0` (done on this
  machine).

---

## Current machine state (2026-08-04)

- `codegraph` 1.5.0 at `/home/nika/.local/bin/codegraph` (npm global, prefix
  `~/.local`)
- Registered in Hermes: `mcp_servers.codegraph` in
  `~/.config/hermes/config.yaml` (`codegraph serve --mcp`, enabled)
- `hermes mcp test codegraph` → Connected (333ms), 1 tool
- Indexed: `~/src/hermes-config` (`.codegraph/`, WAL, gitignored)
- Telemetry: off
- Note: MCP tools load at session start — the tools appear in NEW Hermes
  sessions, not the one that was running when the server was added.

## Sources

- https://github.com/colbymchenry/codegraph (README, MCP tools, troubleshooting)
- npm: https://registry.npmjs.org/@colbymchenry/codegraph (v1.5.0)
- Hermes CLI: `hermes mcp add --help`, `hermes mcp list`, `hermes mcp test`
- Hermes MCP reference: `references/native-mcp.md` in the hermes-agent skill
- CodeGraph package source: `dist/installer/targets/hermes.d.ts`,
  `dist/mcp/session.d.ts`, `dist/installer/instructions-template.d.ts`
