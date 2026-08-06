#!/usr/bin/env bash
# Docker Zero-Trust Sandbox (R4). Changes vs R-04:
#  - PWD guard is an ALLOWLIST (was: 2-entry denylist) — C-2
#  - Protected-path refusal is explicit (credential dirs, system trees, /mnt)
#  - NETWORK allowlisted to none|bridge (container:/host/anything else FATAL) — M-2
#  - MEM_LIMIT/CPU_LIMIT validated before reaching docker — M-2
#  - Interactive TTY auto-detected (works from cron/CI) — M-2
set -Eeuo pipefail
IFS=$'\n\t'

die() { echo "FATAL: $*" >&2; exit 1; }

# ── Allowlist PWD guard ────────────────────────────────────────────────
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
if [ -n "${SANDBOX_ALLOW_DIR:-}" ]; then
  ALLOW_ROOTS+=("$(realpath -e -- "$SANDBOX_ALLOW_DIR" || die "SANDBOX_ALLOW_DIR invalid")")
fi
ok=""
for r in "${ALLOW_ROOTS[@]}"; do
  case "$PWD_REAL" in "$r"|"$r"/*) ok=1;; esac
done
[ -n "$ok" ] || die "PWD '$PWD_REAL' outside sandbox allowlist (${ALLOW_ROOTS[*]}). Set SANDBOX_ALLOW_DIR to extend."
case "$PWD_REAL" in *:*) die "PWD contains ':' — Docker volume syntax break.";; esac

# ── Validated inputs ───────────────────────────────────────────────────
IMAGE="${HERMES_SANDBOX_IMAGE:-hermes-sandbox}"
NETWORK="${NETWORK:-none}"
MEM_LIMIT="${MEM_LIMIT:-4g}"
CPU_LIMIT="${CPU_LIMIT:-2}"

case "$NETWORK" in
  none|bridge) ;;
  *) die "NETWORK='$NETWORK' not allowed (none|bridge only; host/container:* forbidden)" ;;
esac
[[ "$MEM_LIMIT" =~ ^[0-9]+[bkmgtBKMGT]?$ ]] || die "MEM_LIMIT='$MEM_LIMIT' invalid (e.g. 4g)"
[[ "$CPU_LIMIT" =~ ^[0-9]+(\.[0-9]+)?$ ]]   || die "CPU_LIMIT='$CPU_LIMIT' invalid (e.g. 2)"

docker image inspect "$IMAGE" >/dev/null 2>&1 || {
  echo "FATAL: Image '$IMAGE' not found. Build it first:" >&2
  echo "  docker build -t hermes-sandbox $(cd "$(dirname "$0")/.." && pwd)/sandbox" >&2
  exit 1
}

MOUNT_OPTS="ro"
[ "${SANDBOX_RW:-0}" = "1" ] && MOUNT_OPTS="rw"

SECCOMP_ARGS=()
# R-14: default to the repo's hardened seccomp profile when present; opt out
# with SECCOMP_PROFILE=none (or point SECCOMP_PROFILE at a custom path).
if [ -z "${SECCOMP_PROFILE:-}" ]; then
  REPO_PROFILE="$(cd "$(dirname "$0")/.." && pwd)/sandbox/hermes-seccomp.json"
  [ -f "$REPO_PROFILE" ] && SECCOMP_PROFILE="$REPO_PROFILE"
fi
if [ -n "${SECCOMP_PROFILE:-}" ] && [ "$SECCOMP_PROFILE" != "none" ]; then
  SECCOMP_ARGS=(--security-opt "seccomp=$SECCOMP_PROFILE")
fi

RUN_FLAGS=(--rm -i)
[ -t 0 ] && RUN_FLAGS+=(-t)

exec docker run "${RUN_FLAGS[@]}" \
  --init \
  --user "$(id -u):$(id -g)" \
  --security-opt no-new-privileges:true \
  --cap-drop ALL \
  --read-only \
  --tmpfs /tmp:rw,noexec,nosuid,size=512m \
  --tmpfs /scratch:rw,noexec,nosuid,size=1g \
  --memory "$MEM_LIMIT" \
  --memory-swap "$MEM_LIMIT" \
  --pids-limit 256 \
  --ulimit nofile=1024:2048 \
  --ulimit nproc=256:256 \
  --cpus "$CPU_LIMIT" \
  "${SECCOMP_ARGS[@]}" \
  --network "$NETWORK" \
  -v "$PWD_REAL:/work:${MOUNT_OPTS},rprivate" \
  -w /work \
  "$IMAGE" \
  bash "$@"
