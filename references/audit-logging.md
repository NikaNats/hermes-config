# Audit Logging (spec 5.7)

## What Hermes already records on this machine

- Session store: every prompt, tool call, command, and reply is persisted in
  the session DB (retrievable via session_search).
- `~/.config/hermes/logs/agent.log` — runtime log.
- `~/.config/hermes/logs/errors.log` — error log.
- `~/.config/hermes/logs/curator/` — skill/maintenance activity.

## Target structured entry (schema to match when exporting)

    {
      "timestamp": "2026-06-17T12:00:00Z",
      "persona": "coding",
      "tool": "shell",
      "command": "git status --short",
      "cwd": "/home/dev/src/project-alpha",
      "exit_code": 0,
      "approval": "not_required"
    }

Minimum useful fields: user prompt, persona/profile, tool calls, commands,
exit codes, files read/written, diffs, model version/profile, timestamp.

## Rotation (apply manually — the agent cannot sudo)

    sudo tee /etc/logrotate.d/hermes <<'EOF'
    /home/nika/.config/hermes/logs/*.log {
        weekly
        rotate 8
        compress
        delaycompress
        missingok
        notifempty
    }
    EOF
