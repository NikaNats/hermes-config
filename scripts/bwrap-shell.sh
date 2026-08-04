#!/usr/bin/env bash
# Bubblewrap restricted shell: read-only root, tmpfs /tmp and sensitive dirs,
# private pid/uts namespaces, dies with the parent. Additive layer only — NOT
# a full container sandbox. Requires bubblewrap + user namespaces in the kernel.
set -Eeuo pipefail
IFS=$'\n\t'

# bwrap cannot create mount points under a read-only root, so only tmpfs over
# dirs that actually exist. Sensitive dirs are shadowed when present.
TMPFS_ARGS=()
for d in "$HOME/.ssh" "$HOME/.aws" "$HOME/.config/gcloud"; do
  [ -d "$d" ] && TMPFS_ARGS+=(--tmpfs "$d")
done

# Opt-in network isolation: SANDBOX_NO_NET=1 adds --unshare-net.
NET_ARGS=()
[ "${SANDBOX_NO_NET:-0}" = "1" ] && NET_ARGS+=(--unshare-net)

bwrap \
  --ro-bind / / \
  --tmpfs /tmp \
  "${TMPFS_ARGS[@]}" \
  --bind "$PWD" "$PWD" \
  --proc /proc \
  --dev /dev \
  --unshare-pid \
  --unshare-uts \
  "${NET_ARGS[@]}" \
  --die-with-parent \
  bash
