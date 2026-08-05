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

# Build: docker build -t hermes-sandbox sandbox/
# Run:   scripts/run-sandbox.sh
