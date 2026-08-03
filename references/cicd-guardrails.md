# CI/CD Guardrails (spec 5.9)

## Hermes may

- propose CI changes
- debug failed pipelines
- generate test commands
- update workflows in a branch

## Hermes must not

- access production secrets
- push directly to protected branches
- deploy without human approval
- modify CI secrets
- bypass branch protection
- disable required checks

## Preferred workflow (requires gh auth; not logged in yet — `gh auth login`)

    git switch -c ci/improve-tests
    # edit workflows
    git commit
    git push -u origin ci/improve-tests
    gh pr create --fill

No remote is configured for ~/src/hermes-config yet; this workflow applies
to the user's projects once a remote exists.
