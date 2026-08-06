# Secrets & Credential Hygiene (spec 5.6)

## Protected paths (agent must not read or transmit)

    ~/.ssh      ~/.aws      ~/.azure    ~/.config/gcloud
    ~/.gnupg    ~/.netrc
    .env        .env.*
    *.pem       *.p12       *.pfx       *.key

## Conventions

- `~/.agentignore` (home) and `.gitignore` (this repo) carry the pattern
  list. Hermes does not enforce .agentignore natively — real enforcement is:
  `security.redact_secrets: true` (set in config.yaml), SOUL.md rule 7, and
  output redaction; the files keep the convention visible and machine-checkable.
- Never put secrets in prompts, commit messages, or logs.

## If credentials must be used

- Inject at runtime (env var / secret store), never inline.
- Do not log them; redact from output.
- Rotate immediately on any suspected leak.

## Scanning (commit-time, verified)

    # Commit-time: pre-commit + gitleaks v8.30.1 (installed, verified)
    pre-commit install
    pre-commit run gitleaks --all-files    # repo-wide baseline scan

    # Optional broader sweep (not installed):
    go install github.com/gitleaks/gitleaks/v8@latest
    gitleaks detect --verbose

    pip install trufflehog  # or official binary
    trufflehog filesystem . --only-verified
