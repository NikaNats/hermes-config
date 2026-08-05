#!/usr/bin/env bash
# Docker Zero-Trust Sandbox (hermes-sandbox image).
# - Drops ALL capabilities, enforces read-only rootfs, no-new-privileges.
# - Host PWD is mounted Read-Only by default (SANDBOX_RW=1 opts in to rw).
# - NETWORK=host is hard-blocked (default network: none).
#
# Env overrides:
#   HERMES_SANDBOX_IMAGE  image name (default hermes-sandbox)
#   NETWORK               none | bridge  (default none — host is forbidden)
#   MEM_LIMIT             e.g. 4g (default 4g)
#   CPU_LIMIT             e.g. 2   (default 2)
#   SANDBOX_RW            1 = mount host PWD read-write (default: read-only)
set -Eeuo pipefail
IFS=$'\n\t'

# ── PWD guard (parity with bwrap-shell.sh) ──────────────────────────
# Refuse to sandbox from broad directories. Even with --cap-drop ALL
# and a non-root user, a rw bind of / or $HOME exposes the full user
# tree to untrusted code.
case "$PWD" in
    "$HOME"|"$HOME/"|"/")
        echo "FATAL: Refusing to sandbox from '$PWD'." >&2
        echo "       cd into a specific project directory first." >&2
        exit 1
        ;;
esac

# Guard against colons in PWD (Docker -v uses ':' as delimiter)
case "$PWD" in
    *:*)
        echo "FATAL: PWD contains ':' — Docker volume syntax break." >&2
        exit 1
        ;;
esac
# ─────────────────────────────────────────────────────────────────────

IMAGE="${HERMES_SANDBOX_IMAGE:-hermes-sandbox}"
NETWORK="${NETWORK:-none}"
MEM_LIMIT="${MEM_LIMIT:-4g}"
CPU_LIMIT="${CPU_LIMIT:-2}"

# Hard block host networking
if [ "$NETWORK" = "host" ]; then
    echo "FATAL: NETWORK=host is forbidden. Sandbox requires network isolation." >&2
    exit 1
fi

if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
    echo "FATAL: Image '$IMAGE' not found. Build it first:" >&2
    echo "  docker build -t hermes-sandbox $(cd "$(dirname "$0")/.." && pwd)/sandbox" >&2
    exit 1
fi

# Default to Read-Only host mount. Opt-in to RW via SANDBOX_RW=1
MOUNT_OPTS="ro"
if [ "${SANDBOX_RW:-0}" = "1" ]; then
    MOUNT_OPTS="rw"
fi

# R-04: kernel-resource containment. --memory-swap = --memory disables swap
# spill onto the host; --pids-limit ceilings fork bombs; ulimits bound FDs and
# processes. Seccomp: Docker's default profile applies unless
# --security-opt seccomp=unconfined; set SECCOMP_PROFILE=/path/seccomp.json to
# drop in a tighter profile (must be a full replacement profile).
SECCOMP_ARGS=()
if [ -n "${SECCOMP_PROFILE:-}" ]; then
    SECCOMP_ARGS=(--security-opt "seccomp=$SECCOMP_PROFILE")
fi

exec docker run --rm -it \
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
    -v "$PWD:/work:${MOUNT_OPTS},rprivate" \
    -w /work \
    "$IMAGE" \
    bash "$@"
