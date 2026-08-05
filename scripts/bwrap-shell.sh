#!/usr/bin/env bash
# Bubblewrap restricted shell: Zero-Trust execution.
# - Refuses to run from $HOME or / to prevent broad host exposure.
# - Binds PWD read-write, but applies tmpfs masks OVER the bind (last mount wins).
# - Defaults to strict network isolation (SANDBOX_NET=1 opts in; the legacy
#   SANDBOX_NO_NET=1 flag is now the default behavior and accepted as a no-op).
set -Eeuo pipefail
IFS=$'\n\t'

# 1. Prevent broad host exposure
case "$PWD" in
    "$HOME"|"$HOME/"|"/")
        echo "FATAL: Refusing to sandbox from '$PWD'. Invoke from a specific project directory." >&2
        exit 1
        ;;
esac

# 2. Define sensitive paths to mask
DIRS=("$HOME/.ssh" "$HOME/.aws" "$HOME/.azure" "$HOME/.config/gcloud" "$HOME/.gnupg" "$HOME/.kube" "$HOME/.docker")
FILE_MASKS=("$HOME/.netrc" "$HOME/.bash_history" "$HOME/.zsh_history" "$HOME/.python_history")

TMPFS_ARGS=()
for d in "${DIRS[@]}"; do
    [ -d "$d" ] && TMPFS_ARGS+=(--tmpfs "$d")
done
for f in "${FILE_MASKS[@]}"; do
    [ -f "$f" ] && TMPFS_ARGS+=(--bind /dev/null "$f")
done

# 3. Network isolation by default. Opt-in via SANDBOX_NET=1
NET_ARGS=(--unshare-net)
if [ "${SANDBOX_NET:-0}" = "1" ]; then
    NET_ARGS=()
fi

# 4. Execute bwrap with strict namespace isolation
#    Mount order matters: masks/tmpfs come AFTER --bind "$PWD", so the last
#    mount wins and credential paths stay overlaid even when PWD is inside one.
#    bwrap cannot CREATE mount points under a read-only root (EROFS), so only
#    tmpfs over paths that exist on the host: /tmp and /var/tmp always provide
#    fresh scratch; /workspace is mounted only when the host has such a dir.
WORKSPACE_ARGS=()
[ -d /workspace ] && WORKSPACE_ARGS+=(--tmpfs /workspace)

exec bwrap \
    --ro-bind / / \
    --bind "$PWD" "$PWD" \
    --tmpfs /tmp \
    --tmpfs /var/tmp \
    "${WORKSPACE_ARGS[@]}" \
    "${TMPFS_ARGS[@]}" \
    --proc /proc \
    --dev /dev \
    --unshare-pid \
    --unshare-uts \
    --unshare-ipc \
    --new-session \
    "${NET_ARGS[@]}" \
    --die-with-parent \
    --chdir "$PWD" \
    bash
