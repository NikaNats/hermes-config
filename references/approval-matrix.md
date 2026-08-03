# Approval Matrix (spec 3.6)

Behavioral baseline. The hard rules live in `$HERMES_HOME/SOUL.md` (safety
boundaries) and `approvals.deny` / `approvals.smart_policy` in config.yaml;
this table is the shared reference.

| Action | Hermes Default | Confirmation Required |
|---|---:|---:|
| Read source files | Allowed | No |
| Read logs | Allowed | No |
| Run tests | Allowed | No |
| Run linters/formatters | Allowed | No |
| Modify tracked source files | Allowed with diff review | Yes |
| Create new files in project | Allowed | Yes |
| Delete files | Disallowed or strict | Yes, typed confirmation |
| Install dependencies | Propose only | Yes |
| Upgrade dependencies | Propose only | Yes |
| Run database migrations | Propose only | Yes |
| Modify `/etc` | Disallowed by default | Yes, explicit |
| Restart services | Propose only | Yes |
| Use `sudo` | Disallowed by default (deny rule) | Yes, explicit (human runs it) |
| Force-push Git history | Disallowed (deny rule) | Yes, explicit |
| Cloud infrastructure apply | Disallowed | Manual human action |
| Delete cloud resources | Disallowed | Manual human action |

Defense in depth (spec 3.5): Hermes-level permissions → OS user permissions →
filesystem allowlists → command allow/denylists → timeouts/resource limits →
containers/bubblewrap for risky work → git backups before changes → confirmation
prompts.
