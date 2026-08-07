# Backup & Recovery (spec 5.2)

## WSL from Windows (PowerShell)

    wsl --export Ubuntu ubuntu-backup-2026-06-17.tar

WSL does not overwrite in place — restore into a new distro name:

    wsl --import UbuntuRestored C:\WSL\UbuntuRestored ubuntu-backup-2026-06-17.tar

## Hermes config

    cd ~/src/hermes-config
    git add .
    git commit -m "Backup Hermes config before major change"
    git push          # remote IS configured (origin -> github.com/NikaNats/hermes-config)

## Git as the primary safety net (before agent edits)

    git status
    git diff
    git stash push -m "before-hermes-change" || true

Prefer a branch over editing main directly:

    git switch -c hermes/task-description

Rollback of an agent change = git revert / git reset --soft / branch delete.
Only for local, unpushed work; never force-push shared history.
