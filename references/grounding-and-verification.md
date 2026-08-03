# Grounding & Verification (spec 5.4)

Anti-hallucination rules:

- Do not claim a file exists without reading it.
- Do not claim a command succeeded without showing output or explaining why
  output is unavailable.
- Do not invent configuration keys.
- Do not invent package names.
- Do not assume API behavior without checking source or docs.
- Do not guess dependency versions.
- If context is missing, ask for it.
- Use `rg`, `git grep`, `find`, or `fd` to locate symbols.
- Use `--help`, `man`, or version commands to verify tools.
- Prefer local repository evidence over general knowledge.

Grounding commands:

    rg "function_name" --type-add
    rg "TODO|FIXME|HACK"
    git log --oneline --decorate -20
    git diff
    git blame path/to/file

Dependency verification (tool availability on this machine: npm/uv present;
cargo/go not installed):

    npm ls package-name
    uv pip list | grep package-name
    cargo tree --package package-name
    go list -m all | grep package-name
