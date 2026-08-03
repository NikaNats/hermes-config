# Testing & Validation Requirements (spec 5.8)

Production coding tasks end with validation. Tool availability on this
machine: node/npm/uv present; cargo/go not installed (lines below are for
the projects that use them).

Generic checklist (best-effort; never fake a green):

    # Syntax/build
    npm run build || true
    uv run python -m compileall . || true
    cargo check || true
    go build ./... || true

    # Lint/format
    npm run lint || true
    uv run ruff check . || true
    cargo clippy || true

    # Tests
    npm test || true
    uv run pytest -q || true
    cargo test || true
    go test ./... || true

Critical changes additionally require: unit tests, integration tests where
possible, lint/type checks, security scan, dependency audit, manual smoke
test steps.

Security/dependency scans (tools not installed yet):

    npm audit --omit=dev
    pip-audit
    cargo audit
    go run github.com/golangci/golangci-lint/cmd/golangci-lint@latest run

Secret scanning:

    gitleaks detect --verbose
    trufflehog filesystem . --only-verified
