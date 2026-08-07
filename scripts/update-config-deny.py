#!/usr/bin/env python3
"""update-config-deny.py — atomic approvals.deny restorer (2026-08-07 audit / R-15).

Merges the canonical deny list from references/deny-patterns.json into
$HERMES_HOME/config.yaml. Merge-never-replace: existing patterns are preserved
in order; only missing canonical patterns are appended. Also enables the
hardline-gate plugin (preserving the existing plugins.enabled list, including
hermes-lcm and rtk-rewrite). Idempotent; safe to re-run.

Secrets never touch this file — config.yaml holds no secrets (they live in
.env), and this script only touches approvals.deny + plugins.enabled.

Usage:
    HERMES_HOME=/home/nika/.config/hermes python3 scripts/update-config-deny.py
"""

import json
import os
import sys
import tempfile

import yaml

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
CANONICAL = os.path.join(REPO, "references", "deny-patterns.json")
HOME = os.environ.get("HERMES_HOME") or os.path.expanduser("~/.config/hermes")
CFG = os.path.join(HOME, "config.yaml")


def main():
    if not os.path.isfile(CANONICAL):
        sys.exit(f"FATAL: canonical deny list not found: {CANONICAL}")
    if not os.path.isfile(CFG):
        sys.exit(f"FATAL: {CFG} not found — run `hermes setup` or set HERMES_HOME")

    with open(CANONICAL, "r", encoding="utf-8") as fh:
        canonical = json.load(fh).get("deny") or []
    if len(canonical) < 137:
        sys.exit(f"FATAL: canonical deny list suspiciously small ({len(canonical)}); refusing to apply")

    with open(CFG, "r", encoding="utf-8") as fh:
        cfg = yaml.safe_load(fh) or {}

    approvals = cfg.setdefault("approvals", {})
    existing = approvals.get("deny")
    if not isinstance(existing, list):
        existing = []
    merged = list(existing)
    added = 0
    for pattern in canonical:
        if pattern not in merged:
            merged.append(pattern)
            added += 1
    approvals["deny"] = merged
    approvals.setdefault("mode", "smart")
    approvals.setdefault("cron_mode", "deny")

    plugins = cfg.setdefault("plugins", {})
    enabled = plugins.get("enabled")
    if not isinstance(enabled, list):
        enabled = []
    if "hardline-gate" not in enabled:
        enabled.append("hardline-gate")
    plugins["enabled"] = enabled

    # Parity with the audited machine (readiness asserts these): merge, never
    # replace — sibling keys inside each block are preserved.
    sec = cfg.setdefault("security", {})
    sec["redact_secrets"] = True
    sec["tirith_enabled"] = True
    log = cfg.setdefault("logging", {})
    log.setdefault("level", "INFO")

    fd, tmp = tempfile.mkstemp(dir=HOME, prefix=".config.yaml.", suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            yaml.safe_dump(cfg, fh, sort_keys=False, default_flow_style=False)
        os.replace(tmp, CFG)
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise

    print(
        f"SUCCESS: approvals.deny now {len(merged)} patterns "
        f"(added {added}); plugins.enabled={enabled}"
    )


if __name__ == "__main__":
    main()
