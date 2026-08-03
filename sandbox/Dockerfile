FROM ubuntu:26.04

# Aligned with the WSL2 host (Ubuntu 26.04 LTS "Resolute Raccoon").
# Package versions VERIFIED against ubuntu:26.04 on 2026-08-03
# (docker run --rm ubuntu:26.04 sh -c 'apt-cache policy ...').
# If an apt repository update bumps a package, relax the pin (e.g. python3=3.14.*)
# or bump it to the new candidate with the same verification step.
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential=12.12ubuntu2.26.04.2 \
    git=1:2.53.0-1ubuntu1 \
    python3=3.14.3-0ubuntu2 \
    python3-venv=3.14.3-0ubuntu2 \
    nodejs=22.22.1+dfsg+~cs22.19.15-1ubuntu1 \
    npm=9.2.0~ds3-1 \
    jq=1.8.1-4ubuntu2 \
    ripgrep=15.1.0-1ubuntu1 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /work

# Build: docker build -t hermes-sandbox sandbox/
# Run:   scripts/run-sandbox.sh
