#!/usr/bin/env python3
"""secret-scan-store.py — read-only audit of Hermes storage for historical secrets.

Reports LOCATIONS ONLY (never values) where known secret-shaped patterns appear
in Hermes stores: SQLite databases (lcm.db, state.db, ...), their WAL tails, and
logs. Intended to bound the exposure window left by pre-redaction history.

Usage:
    python3 scripts/secret-scan-store.py [ROOT]
        ROOT defaults to $HERMES_HOME (or ~/.hermes).
        Exit 0 = clean; exit 1 = potential hit(s) found (triage required).
"""
import os
import re
import sqlite3
import sys

# The PEM pattern is assembled from fragments so the source does not itself
# contain a literal secret-shaped string (pre-commit gitleaks safety).
PEM_HEAD = "-----BEGIN "
PEM_BODY = "[A-Z0-9 ]*"
PEM_TAIL = "PRIVATE KEY" + "-----"

PATTERNS = {
    "private_key_pem": re.compile(PEM_HEAD + PEM_BODY + PEM_TAIL),
    "aws_access_key": re.compile(r"\bAKIA[0-9A-Z]{16}\b"),
    "github_pat": re.compile(r"\bgh[pousr]_[A-Za-z0-9]{30,255}\b"),
    "openai_like": re.compile(r"\bsk-[A-Za-z0-9_-]{20,}\b"),
    "stripe": re.compile(r"\b(sk|pk|rk)_(live|test)_[A-Za-z0-9]{10,}\b"),
    "slack": re.compile(r"\bxox[baprs]-[A-Za-z0-9-]{10,}\b"),
    "bearer_token": re.compile(r"\bBearer\s+[A-Za-z0-9._-]{20,}"),
    "key_assignment": re.compile(
        r"(?i)\b(api[_-]?key|access[_-]?token|secret[_-]?key"
        r"|client[_-]?secret|auth[_-]?token)\b\s*[:=]\s*['\"]?[A-Za-z0-9_-]{16,}"
    ),
    "password_assignment": re.compile(
        r"(?i)\b(password|passwd|pwd|passphrase)\b\s*[:=]\s*['\"]?\S{4,}"
    ),
}

hits = 0


def scan_text(text, where):
    global hits
    for name, rx in PATTERNS.items():
        if rx.search(text):
            hits += 1
            print(f"HIT [{where} :: {name}]")   # location only, never the value


def scan_db(path):
    try:
        con = sqlite3.connect(f"file:{path}?mode=ro", uri=True)
    except sqlite3.Error as e:
        print(f"SKIP {path}: {e}", file=sys.stderr)
        return
    cur = con.cursor()
    try:
        tables = [t for (t,) in cur.execute(
            "SELECT name FROM sqlite_master WHERE type='table'")]
    except sqlite3.Error:
        tables = []
    for t in tables:
        try:
            cols = [c[1] for c in cur.execute(f'PRAGMA table_info("{t}")')]
            for row in cur.execute(f'SELECT rowid, * FROM "{t}"'):
                for i, v in enumerate(row[1:]):
                    if isinstance(v, str) and len(v) >= 8:
                        scan_text(v, f"{os.path.basename(path)}:{t}[{row[0]}].{cols[i]}")
        except sqlite3.Error:
            pass   # WITHOUT ROWID / virtual tables — wrap & continue
    con.close()


def main(root):
    global hits
    if not os.path.isdir(root):
        print(f"FATAL: not a directory: {root}", file=sys.stderr)
        return 2
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames
                       if d not in ("__pycache__", ".git", "node_modules")]
        for f in sorted(filenames):
            p = os.path.join(dirpath, f)
            if f.endswith((".db", ".sqlite", ".sqlite3")):
                scan_db(p)
            elif f.endswith((".log", ".db-wal")) or (
                    f.endswith(".json") and "payload" in dirpath):
                try:
                    with open(p, errors="ignore") as fh:
                        for n, line in enumerate(fh, 1):
                            scan_text(line, f"{p}:{n}")
                except OSError:
                    pass
    print("RESULT:", "CLEAN" if hits == 0 else
          f"{hits} potential hit(s) — triage required")
    return 0 if hits == 0 else 1


if __name__ == "__main__":
    root = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser(
        os.environ.get("HERMES_HOME", "~/.hermes"))
    sys.exit(main(root))
