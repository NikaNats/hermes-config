# hermes-config

Version-controlled Hermes Agent prompt configuration (SOUL.md + personas).

## Layout

    SOUL.md                              # Global base identity & safety charter
    prompts/
      base.md -> ../SOUL.md              # Symlinked so the base layer is never duplicated
      coding.md                          # Production coding persona
      review.md                          # Code review persona
      ops.md                             # System administration persona
      research.md                        # Research/document analysis persona
      automation.md                      # Workflow automation persona
      production.md                      # Spec 6.1 production ops persona (plan/evidence/stop)
      scripts/assemble-prompt.sh         # Concatenates SOUL.md + persona into an active prompt

## Tooling & References (spec 3 & 4)

    references/
      approval-matrix.md                 # Spec 3.6 approval matrix & defense in depth
      toolchains.md                      # Spec 3.4 canonical per-language validation commands
      document-parsing.md                # Spec 4.1 doc/PDF/CSV tooling + analysis prompt
      log-analysis.md                    # Spec 4.2 log tools, workflow, analysis prompt
      sysadmin-readonly.md               # Spec 4.3 read-only sysadmin + narrow sudoers notes
      sudoers-hermes-readonly.example    # Spec 4.3 narrow read-only sudoers (apply manually)
      research-workflow.md               # Spec 4.4 research workflow + injection defenses
      reporting-artifacts.md             # Spec 4.5 report dir convention & template
      safety-model.md                    # Spec 5.1 layered operational safety model
      backup-recovery.md                 # Spec 5.2 WSL/config backup + git safety net
      safe-interaction-patterns.md       # Spec 5.3 read-only-first, plan, evidence patterns
      grounding-and-verification.md      # Spec 5.4 anti-hallucination grounding rules
      destructive-commands.md            # Spec 5.5 destructive command policy + trash
      secrets-hygiene.md                 # Spec 5.6 credential hygiene + .agentignore
      audit-logging.md                   # Spec 5.7 audit log schema + logrotate
      validation-checklist.md            # Spec 5.8 build/lint/test + security scans
      cicd-guardrails.md                 # Spec 5.9 CI/CD allowed/denied + PR workflow
      prompt-injection-defense.md        # Spec 5.10 injection defense block + rules
      production-profile.md              # Spec 6.1 blueprint -> real control mapping
      preflight-checklist.md             # Spec 6.3 read-only pre-flight before edits
      sandbox/
      Dockerfile                         # Spec 3.8 hermes-sandbox image (ubuntu 24.04)
    scripts/
      run-sandbox.sh                     # Spec 3.8 docker runner (resource/network limits)
      bwrap-shell.sh                     # Spec 3.9 bubblewrap restricted shell
      new-report.sh                      # Spec 4.5 dated report artifact creator
      trash.sh                           # Spec 5.5 trash instead of delete helper
      hermes-project-init                # Spec 6.2 safe project bootstrap (symlinked to ~/bin)
      templates/
        safe-script.sh                   # Spec 3.2 default safe header for generated scripts
        report.md                        # Spec 4.5 Markdown report template
    .gitignore                           # Spec 5.6 secret/credential ignore patterns

## Install (symlink into the live Hermes home)

    ln -sf ~/src/hermes-config/SOUL.md   ~/.config/hermes/SOUL.md
    ln -sf ~/src/hermes-config/SOUL.md   ~/.hermes/SOUL.md        # legacy home, if present
    ln -sf ~/src/hermes-config/prompts   ~/.config/hermes/prompts

Hermes loads `$HERMES_HOME/SOUL.md` automatically as the agent identity
(Layer 1 of the cached system prompt) on every new session. The prompts/
directory is a modular library; the base layer is SOUL.md itself, so a persona
file is only ever a diff on top of it.

## Using a persona

- The persona files are the building blocks. To activate one for a session,
  concatenate base + persona (see scripts/assemble-prompt.sh) and feed the
  result as the system message, or copy it into the session prompt manually.
- Editing: change a file here, commit, and the symlinks pick it up instantly.
  SOUL.md changes apply to NEW sessions (the cached system prompt is frozen
  mid-conversation by design).

## Maintenance

- Review prompt changes like code changes: small diffs, explicit rationale.
- Keep personas short to avoid context pollution.
- Use MUST / DO NOT / explicit stop conditions; avoid contradictory
  instructions between layers (base wins on safety, persona wins on method).
