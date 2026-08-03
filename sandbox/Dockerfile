FROM ubuntu:24.04

RUN apt-get update && apt-get install -y \
    build-essential \
    git \
    python3 \
    python3-venv \
    nodejs \
    npm \
    jq \
    ripgrep \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /work

# Build: docker build -t hermes-sandbox sandbox/
# Run:   scripts/run-sandbox.sh
