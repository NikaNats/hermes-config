#!/usr/bin/env bash
# Run a hermes-sandbox container for risky tasks (dependency installs,
# untrusted code, experiments). Build once with:
#   docker build -t hermes-sandbox sandbox/
#
# Env overrides:
#   HERMES_SANDBOX_IMAGE  image name (default hermes-sandbox)
#   NETWORK               none | bridge | host  (default none — no outbound network)
#   MEM_LIMIT             e.g. 4g (default 4g)
#   CPU_LIMIT             e.g. 2   (default 2)
set -Eeuo pipefail
IFS=$'\n\t'

IMAGE="${HERMES_SANDBOX_IMAGE:-hermes-sandbox}"
NETWORK="${NETWORK:-none}"
MEM_LIMIT="${MEM_LIMIT:-4g}"
CPU_LIMIT="${CPU_LIMIT:-2}"

if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
  echo "Image '$IMAGE' not found. Build it first:" >&2
  echo "  docker build -t hermes-sandbox $(cd "$(dirname "$0")/.." && pwd)/sandbox" >&2
  exit 1
fi

exec docker run --rm -it \
  --init \
  --user "$(id -u):$(id -g)" \
  --security-opt no-new-privileges:true \
  --memory "$MEM_LIMIT" \
  --cpus "$CPU_LIMIT" \
  --network "$NETWORK" \
  -v "$PWD:/work" \
  -w /work \
  "$IMAGE" \
  bash
