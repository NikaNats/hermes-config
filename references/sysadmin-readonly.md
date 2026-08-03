# System Administration Automation (spec 4.3)

Hermes helps manage WSL/Linux services, but defaults to read-only.

## Read-only first

Safe read-only examples (no sudo needed for most on a systemd WSL setup):

    systemctl list-units --state=failed
    systemctl status ssh
    systemctl list-timers --all
    journalctl --disk-usage

## Narrow sudoers (optional, apply manually)

Controlled privileged commands CAN be allowed through narrow sudoers rules —
only if you decide the convenience is worth removing the password prompt for
those exact commands. A ready file is at:

    references/sudoers-hermes-readonly.example

Apply (run yourself — the agent cannot sudo by policy):

    sudo install -m 0440 -o root -g root \
      ~/src/hermes-config/references/sudoers-hermes-readonly.example \
      /etc/sudoers.d/hermes-readonly
    sudo visudo -c        # must print "parsed OK"

Rollback:

    sudo rm /etc/sudoers.d/hermes-readonly

## Never

Broad sudo is forbidden:

    nika ALL=(ALL) NOPASSWD: ALL      # NEVER — unrestricted root for the agent

Even with narrow rules, keep the `approvals.deny: ["sudo *"]` policy in
config.yaml: it means the AGENT can never invoke sudo itself; narrow sudoers
only lets passwordless read-only diagnostics run when the USER runs them.
