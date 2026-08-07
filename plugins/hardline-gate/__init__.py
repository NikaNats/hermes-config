"""hardline-gate — deterministic pre-execution command scanner (C-1 fix).

Bridges Hermes ``pre_tool_call`` hooks to ``scripts/hardline-check.sh`` so the
hardline scanner runs on EVERY terminal command instead of only when the
Guardian LLM decides to invoke it (smart_policy rule 9).

Contract (verified against Hermes source, hermes_cli/plugins.py): a
``pre_tool_call`` hook returns either ``None`` (allow, observer mode) or a
dict ``{"action": "block", "message": "..."}`` (veto — the message becomes the
tool result the model sees). Invalid return values are silently ignored.

Fail-closed: scanner missing, not executable, timing out, or erroring => block.
The plugin only ever reads the command string and runs the scanner — it never
modifies the command (contrast with rtk-rewrite, which rewrites).
"""

import os
import subprocess
import sys

_checked = False
_script_path = None
_missing_warned = False

_SCANNER_CANDIDATES = (
    os.path.expanduser("~/src/hermes-config/scripts/hardline-check.sh"),
    os.path.join(
        os.environ.get("HERMES_HOME", os.path.expanduser("~/.config/hermes")),
        "scripts/hardline-check.sh",
    ),
)


def register(ctx):
    """Register the Hermes pre-tool-call hook. Always registers (fail-closed
    is enforced at call time when the scanner is missing)."""
    ctx.register_hook("pre_tool_call", _pre_tool_call)


def _resolve_scanner():
    """Locate hardline-check.sh. Repo copy wins; fall back to HERMES_HOME/scripts."""
    global _checked, _script_path, _missing_warned
    if _checked:
        return _script_path
    _checked = True
    for candidate in _SCANNER_CANDIDATES:
        if os.path.isfile(candidate) and os.access(candidate, os.X_OK):
            _script_path = candidate
            return _script_path
    if not _missing_warned:
        _missing_warned = True
        print(
            f"hardline-gate: scanner not found in {list(_SCANNER_CANDIDATES)}; "
            "failing closed on all terminal commands",
            file=sys.stderr,
        )
    return None


def _block(message):
    return {"action": "block", "message": message}


def _pre_tool_call(tool_name=None, args=None, **_kwargs):
    """Deterministic gate: block terminal/shell commands the scanner rejects."""
    if tool_name not in ("terminal", "shell", "bash"):
        return None
    if not isinstance(args, dict):
        return None
    command = args.get("command")
    if not isinstance(command, str) or not command.strip():
        return None

    script = _resolve_scanner()
    if script is None:
        return _block(
            "HARDLINE GATE ERROR: scanner missing — command blocked (fail-closed). "
            "Restore scripts/hardline-check.sh (repo: ~/src/hermes-config)."
        )

    try:
        result = subprocess.run(
            [script, command],
            shell=False,
            timeout=5,
            capture_output=True,
            text=True,
        )
    except subprocess.TimeoutExpired:
        return _block("HARDLINE GATE ERROR: scanner timed out — command blocked (fail-closed).")
    except Exception as e:  # noqa: BLE001 — fail closed on any invocation error
        return _block(f"HARDLINE GATE ERROR: scanner invocation failed ({e}) — command blocked (fail-closed).")

    if result.returncode != 0:
        detail_lines = (result.stderr or result.stdout or "").strip().splitlines()
        reason = detail_lines[-1] if detail_lines else "blocked by hardline policy"
        return _block(f"HARDLINE GATE BLOCKED: {reason}")
    return None
