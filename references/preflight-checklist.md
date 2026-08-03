# Pre-Flight Checklist (spec 6.3)

Run before Hermes changes code:

    git status --short --branch
    git stash list
    git log --oneline --decorate -5
    rg --files | head

Then hand Hermes this read-only prompt:

    You are in read-only mode. Inspect the project and produce:
    1. Current state
    2. Relevant files
    3. Risks
    4. Missing information
    5. Proposed implementation plan

    Do not modify files.

Pairs with Pattern 1 (read-only first) in
references/safe-interaction-patterns.md.
