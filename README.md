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
    scripts/assemble-prompt.sh           # Concatenates SOUL.md + persona into an active prompt

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
    sandbox/
      Dockerfile                         # Spec 3.8 hermes-sandbox image (ubuntu 24.04)
    scripts/
      run-sandbox.sh                     # Spec 3.8 docker runner (resource/network limits)
      bwrap-shell.sh                     # Spec 3.9 bubblewrap restricted shell
      new-report.sh                      # Spec 4.5 dated report artifact creator
      templates/
        safe-script.sh                   # Spec 3.2 default safe header for generated scripts
        report.md                        # Spec 4.5 Markdown report template

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
