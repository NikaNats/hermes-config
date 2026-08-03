# Production Profile Blueprint (spec 6.1)

Concept -> real control mapping for this machine. Hermes has no single
"profile: production" key; the blueprint is realized across layers already
built in Sections 2-5. The behavior block is realized as a persona
(`prompts/production.md`); the rest maps onto existing controls.

| Blueprint key                | Real control | Where |
|---|---|---|
| behavior.planning_required   | plan-before-execute persona rule | prompts/production.md |
| behavior.evidence_required   | SOUL.md principle 3 + Pattern 3 | SOUL.md, references/safe-interaction-patterns.md |
| behavior.destructive_actions | approvals.mode=smart + deny list | config.yaml approvals.* |
| behavior.output_format      | SOUL.md output discipline + report template | SOUL.md, scripts/templates/report.md |
| behavior.stop_when_uncertain | ask-one-question rule + Pattern 5 | SOUL.md, references/safe-interaction-patterns.md |
| behavior.temperature         | NOT settable per persona; model/provider level | n/a |
| permissions.filesystem.*     | NOT natively supported (no per-path ACLs); closest: OS user perms, ~/agent layout, .agentignore, redact_secrets | references/secrets-hygiene.md |
| permissions.shell.*          | smart_policy + deny list | config.yaml approvals.smart_policy |
| permissions.git.*            | deny list + smart policy (commits/push flagged for approval) | config.yaml approvals.deny |
| permissions.network.*        | SOUL.md rule 7 (no credentials) + principle 8 (untrusted content) | SOUL.md |

Unsupported keys (temperature, filesystem ACLs) are documented gaps: the
nearest real controls are model/provider settings and OS-level user
permissions respectively. Do not invent config keys to fake them.
