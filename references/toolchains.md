# Developer Toolchains (spec 3.4)

Use the project's own tooling before inventing commands. Discovery first, then the
project's canonical validation commands.

## Generic discovery

    ls -la
    cat package.json
    cat pyproject.toml
    cat Cargo.toml
    cat Makefile
    cat docker-compose.yml

## Python (uv)

    uv sync
    uv run ruff check .
    uv run ruff format .
    uv run mypy .
    uv run pytest -q

## Node (npm)

    npm ci
    npm run lint
    npm run test
    npm run build

## pnpm

    pnpm install --frozen-lockfile
    pnpm lint
    pnpm test
    pnpm build

## Rust

    cargo fmt --check
    cargo clippy --all-targets --all-features -- -D warnings
    cargo test

## Go

    go fmt ./...
    go vet ./...
    go test ./...

## Docker

    docker compose config
    docker compose build
    docker compose run --rm app npm test

Always prefer `timeout` wrappers on the long ones (npm test, cargo test, builds).
