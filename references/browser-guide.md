# Browser Automation — Production Implementation Guide for Hermes Agent

**Revision:** v1.0 (verified against Hermes source + live install, 2026-08-04)
**Status on this machine:** local side installed (agent-browser 0.27.0 + Chromium),
`browser:` config hardened; Firecrawl/Camofox NOT deployed (see Phase 7).

> Every config key and command in this guide was verified against the installed
> Hermes source (`hermes_cli/config_defaults.py`, `tools/browser_tool.py`,
> `agent/browser_provider.py`, `hermes_cli/env_loader.py`) and/or executed on
> this machine on 2026-08-04. Items marked ADVICE are recommendations.

---

## Executive Summary

Hermes has a native browser toolset (`browser_navigate`, `browser_snapshot`,
`browser_click`, `browser_type`, `browser_console`, `browser_get_images`,
`browser_vision` [gated], plus `/browser connect|disconnect|status` CDP
commands). It supports TWO modes:

- **Local mode** (default, no cloud provider configured): drives a local
  browser via the `agent-browser` CLI (Vercel Labs npm package) over CDP.
- **Cloud mode** (`browser.cloud_provider` set): routes `browser_*` calls to a
  registered cloud provider (built-ins: `browserbase`, `browser-use`,
  `firecrawl` — verified in `plugins/browser/`).

The guide's core concept — **hybrid routing** — is real Hermes behavior:
`browser.auto_local_for_private_urls: true` (the default) auto-spawns local
Chromium for localhost/LAN URLs when a cloud provider is set, instead of
sending private traffic to the cloud.

> ⚠️ **Premise correction:** the original draft assumed an existing
> self-hosted Firecrawl stack and Camofox container. **Neither exists on this
> machine** (verified: `docker ps -a` empty, images = hermes-sandbox/ubuntu/
> hello-world only). Phase 7 documents what standing them up actually
> requires. The local side (Phases 2–4) works standalone.

---

## Phase 1 — Architecture & Hybrid Routing (verified)

| Target URL | Routing | Verdict |
| :--- | :--- | :--- |
| Public Internet | Firecrawl (cloud provider) | Real but requires standing up Firecrawl first (Phase 7) |
| Localhost / LAN | Local Chromium via agent-browser | Real; works in local mode with no extra config |
| Anti-detection | Camofox | Real backend (`browser.camofox` block, `CAMOFOX_URL`); installed via npm, NOT `docker run camofox-browser` |

Key security semantics (verified in `tools/browser_tool.py`):

- `_is_local_backend()`: when the browser is local AND the terminal is local,
  the **private-IP/SSRF gate is skipped by design** ("the user already has
  full terminal and network access on the same machine"). The gate is
  enforced only for cloud backends, CDP overrides, or containerized
  terminals (`TERMINAL_ENV != local`).
- `browser.allow_private_urls` (default **false**) gates private/internal
  navigation where the SSRF gate applies (cloud/CDP modes).
- A global SSRF deny list for outbound traffic exists in
  `config_defaults.py` (cloud metadata 169.254.169.254, RFC1918) — relevant
  to web tooling and cloud-mode browser calls.

---

## Phase 2 — Local Sidecar Installation (WSL2, verified)

Hermes' local engine is the `agent-browser` CLI — **not** apt Chromium.
Installed and verified on this machine:

```bash
# 1. Install the CLI (npm prefix ~/.local here → /home/nika/.local/bin)
npm install -g agent-browser        # → agent-browser 0.27.0 (needs >= 0.25.3)

# 2. Fetch the browser binary + system deps (this is the actual browser install)
agent-browser install --with-deps
```

> ⚠️ **Do NOT `sudo apt install chromium-browser`** on Ubuntu 26.04
> (resolute): the candidate is the snap transitional package
> `2:1snap1-0ubuntu4` and snapd is inactive in this WSL2. The npm route
> above is Hermes' own recommended install (`hermes_cli/setup.py`).

Verify:

```bash
agent-browser --version   # agent-browser 0.27.0
```

### Cache/recording directories (optional, ADVICE)

Hermes already manages its cache; these are only needed if you record
sessions or inspect artifacts:

```bash
mkdir -p "${HERMES_HOME:-$HOME/.hermes}/cache/web"
mkdir -p "${HERMES_HOME:-$HOME/.hermes}/cache/screenshots"
mkdir -p "${HERMES_HOME:-$HOME/.hermes}/browser_recordings"
```

---

## Phase 3 — Configuration (corrected)

### 1. Env file — correct path

Hermes loads a dotenv at startup (`hermes_cli/env_loader.py` +
`load_hermes_dotenv`). With `HERMES_HOME=/home/nika/.config/hermes` active,
the file to edit is **`$HERMES_HOME/.env`** (i.e.
`~/.config/hermes/.env` on this machine), NOT `~/.hermes/.env`.

```bash
# ${HERMES_HOME:-$HOME/.hermes}/.env
BROWSER_INACTIVITY_TIMEOUT=120   # real legacy env var; default already 120
# Only when you actually run Firecrawl (Phase 7):
# FIRECRAWL_API_KEY=***
# FIRECRAWL_API_URL=http://localhost:3002
```

### 2. config.yaml — verified keys

```yaml
browser:
  # Local mode: DO NOT set cloud_provider until Firecrawl/Camofox exists —
  # a configured-but-dead provider breaks every browser call.
  # cloud_provider: firecrawl          # only after Phase 7
  auto_local_for_private_urls: true    # default true; hybrid routing
  allow_private_urls: false            # default false; gates cloud/CDP modes
  restrict_evaluate: true              # OPT-IN denylist for browser_console(expression=)
  dialog_policy: must_respond          # default; native JS dialogs need agent response
  dialog_timeout_s: 60                 # tightening; default is 300
  headed: false                        # default; headless in WSL2
  record_sessions: false               # default; WebM recording off
```

Applied on this machine (via Python YAML edit, not `hermes config set`):
`restrict_evaluate: true`, `dialog_timeout_s: 60`; everything else stays at
default (local mode, no cloud provider).

### 3. Do NOT run this guide's toolsets command

`hermes config set toolsets '["hermes-cli", "browser", "mcp"]'` is wrong
three ways (verified):

1. **`mcp` is not a toolset name.** The catalog (`toolsets.py`) has `browser`,
   `hermes-cli`, `web`, `terminal`, `file`, `delegation`, … — MCP servers are
   configured separately via `mcp_servers`, not a toolset.
2. **`hermes config set` stores YAML lists as scalar strings** — the value
   would become the literal text `["hermes-cli", "browser", "mcp"]`, not a
   list. List keys must be written as real YAML (Python `yaml.safe_dump`).
3. **Narrowing `toolsets` disables everything else** — setting a custom list
   drops `terminal`, `file`, `web`, etc. from future sessions.

The browser toolset is available by default; you do not need to enable it.
There is also **no `hermes restart` command** — config.yaml is read at
session start, so start a new `hermes chat`.

---

## Phase 4 — Security & LCM Integration (verified)

### 1. LCM large-output externalization — all three env vars REAL

Defaults: externalization OFF, threshold 12000, stubbing OFF. The draft's
recommendations are the correct opt-ins:

```bash
# ${HERMES_HOME}/.env
LCM_LARGE_OUTPUT_EXTERNALIZATION_ENABLED=true
LCM_LARGE_OUTPUT_EXTERNALIZATION_THRESHOLD_CHARS=12000
LCM_LARGE_OUTPUT_ACTIVE_REPLAY_STUBBING_ENABLED=true
```

`browser_snapshot(full=true)` snapshots over 15,000 chars are truncated or
LLM-summarized by the runtime, so externalizing keeps raw DOM out of both the
context and `lcm.db`.

### 2. Browser safety rules — recommended, apply to SOUL.md

`prompts/base.md` is a symlink to `../SOUL.md`, so "add to base.md" means
editing SOUL.md (takes effect in new sessions). The draft's four rules are
sound; keep them aligned with SOUL.md's existing principles (read-only
default, credential hygiene, no cloud-metadata/internal probing outside
scope, vision-over-DOM when Canvas/WebGL obfuscates).

Note: `browser_vision` exists but is gated (requires vision availability /
cloud backend per `cli-config.yaml.example`); it may not appear in every
session. `browser_get_images` + `vision_analyze` is the local fallback.

---

## Phase 5 — Advanced WSL2 Workflows

### A. Headed mode via WSLg — verified env var

```bash
AGENT_BROWSER_HEADED=1 hermes chat
```

`AGENT_BROWSER_HEADED` is read by the browser tool (verified:
`tools/browser_tool.py`, `agent/chat_completion_helpers.py`); it overrides
`browser.headed` and skips per-turn cleanup so the window persists.

### B. Windows-host Chrome via CDP — verified slash command

```powershell
# Windows PowerShell
"C:\Program Files\Google\Chrome\Application\chrome.exe" --remote-debugging-port=9222 --user-data-dir="C:\temp\chrome-debug"
```

```bash
# Inside Hermes: /browser connect ws://localhost:9222
#   (/browser connect|disconnect|status — verified in cli_commands_mixin.py)
```

WSL2 forwards localhost to Windows by default (localhostForwarding=true).
A CDP override is treated as NON-local by the SSRF gate — expected.

### C. Camofox — corrected install (npm, not docker)

The draft's `docker run -d --name camofox -p 9377:9377 camofox-browser` uses
a nonexistent image. Camofox is `jo-inc/camofox-browser` (npm
`@askjo/camofox-browser`); Hermes installs it via `hermes setup`
(post_setup: camofox). Default port 9377 is correct.

```bash
export CAMOFOX_URL=http://localhost:9377
hermes chat
# or configure browser.camofox.* in config.yaml (managed_persistence, user_id, ...)
```

---

## Phase 6 — Testing (corrected expectations)

| Test | Expected (corrected) |
| :--- | :--- |
| 1. Public URL | Only routes through Firecrawl AFTER it is stood up (Phase 7) and `browser.cloud_provider: firecrawl` is set. Without it, local Chromium handles it. |
| 2. Localhost snapshot | Works in local mode out of the box — local backend skips the private-URL gate; no cloud provider needed. |
| 3. SSRF 169.254.169.254 | **Mode-dependent.** Blocked in cloud/CDP/containerized-terminal modes; **allowed in pure local mode by design** (`_is_local_backend()`). The draft's "even if using the local browser" is wrong. |
| 4. `browser_console` evaluate | With `browser.restrict_evaluate: true`, sensitive primitives (cookies/storage/clipboard/network/form values) are denylisted. `allow_unsafe_evaluate: true` is the escape hatch (default false). |

Live smoke test performed on this machine: local HTTP server + local
Chromium navigation + DOM snapshot succeeded (see install notes).

---

## Phase 7 — Firecrawl / Camofox Standing Up (NOT deployed here)

Nothing from the draft's "previous setup" exists. If you want the cloud
routes:

- **Firecrawl self-hosted:** clone the Firecrawl repo and run its
  docker-compose (mendableai/firecrawl); this guide does not verify that
  stack. Then set `FIRECRAWL_API_KEY`/`FIRECRAWL_API_URL` in
  `${HERMES_HOME}/.env` and `browser.cloud_provider: firecrawl` (and/or
  `web.extract_backend: firecrawl` for web_extract).
- **Camofox:** `hermes setup` (npm path) as in Phase 5C.

Both are optional additions; the local side (Phases 2–4) is fully functional
without them.

---

## Summary of the Production Stack

| Layer | Tool | Responsibility |
| :--- | :--- | :--- |
| Public Web Scraping | Firecrawl (self-hosted, optional) | Clean Markdown, bot-protection bypass — NOT deployed yet |
| Interactive / Localhost | agent-browser + Chromium | Installed; fills forms, clicks, reaches WSL2 local dev servers |
| Context Management | Hermes-LCM | LCM_LARGE_OUTPUT_* externalizes 15k DOM snapshots |
| Security | restrict_evaluate + mode-aware SSRF gate | Denylisted JS primitives; gate enforced in cloud/CDP modes |

## Sources

- Hermes source (this install): `hermes_cli/config_defaults.py` (browser
  block, env vars, SSRF deny list), `tools/browser_tool.py`
  (`_is_local_backend`, `_allow_private_urls`, `restrict_evaluate`,
  AGENT_BROWSER_HEADED), `agent/browser_provider.py` (provider ABC),
  `hermes_cli/env_loader.py` (dotenv), `hermes_cli/cli_commands_mixin.py`
  (`/browser connect`), `hermes_cli/tools_config.py` (Camofox setup),
  `toolsets.py` (toolset catalog)
- npm: https://www.npmjs.com/package/agent-browser (Vercel Labs, 0.33.2
  latest; Hermes requires >= 0.25.3)
- Camofox: https://github.com/jo-inc/camofox-browser (npm @askjo/camofox-browser)
- Hermes docs: https://hermes-agent.nousresearch.com/docs (browser guide)
