#!/usr/bin/env bash
# Bubblewrap restricted shell (R4). Changes vs R-05:
#  - Allowlist PWD guard (parity with run-sandbox.sh) — C-2
#  - PWD bound READ-ONLY by default; SANDBOX_RW=1 opts in (Docker parity) — C-2
#  - Optional size-capped tmpfs via BWRAP_TMPFS_SIZE (probed; warns+skips if
#    this bwrap build rejects --size) — L-3
set -Eeuo pipefail
IFS=$'\n\t'
die() { echo "FATAL: $*" >&2; exit 1; }

# ── Allowlist PWD guard (identical semantics to run-sandbox.sh) ────────
PWD_REAL="$(realpath -e -- "$PWD" 2>/dev/null)" || die "cannot resolve PWD"
PROTECTED=(
  "$HOME/.ssh" "$HOME/.aws" "$HOME/.azure" "$HOME/.config/gcloud"
  "$HOME/.gnupg" "$HOME/.kube" "$HOME/.docker" "$HOME/.config/hermes"
  "$HOME/.netrc" "$HOME/.bash_history"
  /etc /boot /usr /bin /sbin /var /root /mnt /media /opt /srv
)
for p in "${PROTECTED[@]}"; do
  case "$PWD_REAL" in "$p"|"$p"/*) die "refusing to sandbox inside protected path: $PWD_REAL";; esac
done
ALLOW_ROOTS=("$HOME/src" "$HOME/agent/workspaces")
[ -n "${SANDBOX_ALLOW_DIR:-}" ] && ALLOW_ROOTS+=("$(realpath -e -- "$SANDBOX_ALLOW_DIR" || die "SANDBOX_ALLOW_DIR invalid")")
ok=""
for r in "${ALLOW_ROOTS[@]}"; do case "$PWD_REAL" in "$r"|"$r"/*) ok=1;; esac; done
[ -n "$ok" ] || die "PWD '$PWD_REAL' outside sandbox allowlist (${ALLOW_ROOTS[*]})"

# ── Masks (after the PWD bind — last mount wins) ───────────────────────
DIRS=("$HOME/.ssh" "$HOME/.aws" "$HOME/.azure" "$HOME/.config/gcloud" "$HOME/.gnupg" "$HOME/.kube" "$HOME/.docker" "$HOME/.config/hermes")
FILE_MASKS=("$HOME/.netrc" "$HOME/.bash_history" "$HOME/.zsh_history" "$HOME/.python_history" "$HOME/.config/hermes/.env" "$HOME/.config/hermes/lcm.db")
MASK_ARGS=()
for f in "${FILE_MASKS[@]}"; do [ -f "$f" ] && MASK_ARGS+=(--bind /dev/null "$f"); done
for d in "${DIRS[@]}";      do [ -d "$d" ] && MASK_ARGS+=(--tmpfs "$d"); done

NET_ARGS=(--unshare-net)
[ "${SANDBOX_NET:-0}" = "1" ] && NET_ARGS=()

# PWD bind mode: read-only default, rw opt-in (Docker parity)
PWD_BIND=(--ro-bind "$PWD_REAL" "$PWD_REAL")
[ "${SANDBOX_RW:-0}" = "1" ] && PWD_BIND=(--bind "$PWD_REAL" "$PWD_REAL")

# Optional tmpfs size cap (probe; bwrap builds differ)
SIZE_ARGS=()
if [ -n "${BWRAP_TMPFS_SIZE:-}" ]; then
  if bwrap --unshare-user --die-with-parent --ro-bind / / --proc /proc --dev /dev \
       --tmpfs /tmp --size "$BWRAP_TMPFS_SIZE" --chdir / true 2>/dev/null; then
    SIZE_ARGS=(--size "$BWRAP_TMPFS_SIZE")
  else
    echo "WARN: this bwrap rejects --size; tmpfs left unbounded" >&2
  fi
fi

WORKSPACE_ARGS=()
[ -d /workspace ] && WORKSPACE_ARGS+=(--tmpfs /workspace)

# User-namespace preflight (fail-closed)
if ! bwrap --unshare-user --die-with-parent --ro-bind / / --proc /proc --dev /dev \
     --unshare-pid --unshare-uts --unshare-ipc --new-session --chdir / true 2>/dev/null; then
  die "bwrap --unshare-user unavailable (kernel.unprivileged_userns_clone=0?)"
fi

exec bwrap \
  --ro-bind / / \
  "${PWD_BIND[@]}" \
  --tmpfs /tmp "${SIZE_ARGS[@]}" \
  --tmpfs /var/tmp \
  "${WORKSPACE_ARGS[@]}" \
  "${MASK_ARGS[@]}" \
  --proc /proc \
  --dev /dev \
  --tmpfs /proc/sys \
  --tmpfs /sys/firmware \
  --unshare-user \
  --unshare-pid \
  --unshare-uts \
  --unshare-ipc \
  --unshare-cgroup-try \
  --new-session \
  "${NET_ARGS[@]}" \
  --die-with-parent \
  --chdir "$PWD_REAL" \
  bash "$@"
