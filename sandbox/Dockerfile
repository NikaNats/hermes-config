FROM ubuntu:26.04

# Aligned with the WSL2 host (Ubuntu 26.04 LTS "Resolute Raccoon").
# Version pins are major.minor wildcards so apt resolves the current candidate
# (exact pins caused apt-get 404 during disaster recovery when repos bumped).
# Re-verify candidates with: docker run --rm ubuntu:26.04 sh -c 'apt-cache policy <pkg>'
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    git=1:2.53.* \
    python3=3.14.* \
    python3-venv=3.14.* \
    nodejs=22.* \
    npm=9.* \
    jq=1.8.* \
    ripgrep=15.* \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /work

# R-06: real non-root sandbox user so --user <host-uid>:<host-gid> maps to a
# passwd entry ($HOME set, whoami/getpwuid() work) instead of a phantom UID.
# Build matched to the host: docker build -t hermes-sandbox \
#   --build-arg SANDBOX_UID="$(id -u)" --build-arg SANDBOX_GID="$(id -g)" sandbox/
ARG SANDBOX_UID=1000
ARG SANDBOX_GID=1000
# Base image ships 'ubuntu' at uid/gid 1000 — remove it first (unused in the
# sandbox), then create the dedicated 'sandbox' user with the host-matched ids.
RUN userdel -r ubuntu 2>/dev/null || true; \
    groupadd -g "${SANDBOX_GID}" sandbox 2>/dev/null || true; \
    useradd -m -u "${SANDBOX_UID}" -g "${SANDBOX_GID}" -s /bin/bash sandbox
ENV HOME=/home/sandbox
USER sandbox

# Build: docker build -t hermes-sandbox sandbox/
# Run:   scripts/run-sandbox.sh
