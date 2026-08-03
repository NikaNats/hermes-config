# Operational Safety Model (spec 5.1)

Layered defense. No single layer is sufficient; every layer maps to a real,
checked artifact in this repo or the OS.

    Layer                     Implementation
    Prompt rules              SOUL.md principles + Safety & Boundaries
    Hermes config permissions config.yaml approvals.* (deny list, smart policy)
    OS user permissions       non-root user (nika); no passwordless sudo
    Filesystem boundaries     ~/agent/{reports,artifacts,downloads,workspaces}; repo tree
    Command policy            references/approval-matrix.md + approvals.deny
    Sandbox/container         sandbox/Dockerfile, scripts/run-sandbox.sh, bwrap-shell.sh
    Git/version control       ~/src/hermes-config (commit before/after changes)
    Human approval            approvals.mode=smart; typed confirmation for destructive ops
    Audit logs                ~/.config/hermes/logs/{agent.log,errors.log}; session DB

Failure model: if one layer fails (a deny pattern too broad or too narrow,
a missing review, a race), the layers above and below still gate the action.
Never rely on a single layer.
