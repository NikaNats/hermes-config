# Safe Interaction Patterns (spec 5.3)

User-facing prompts that reduce hallucinations and destructive behavior.

## Pattern 1: Read-Only First

    Inspect the repository and explain the issue. Do not modify files yet.

    Propose a minimal patch and validation plan. Do not apply it yet.

    Apply the patch and run tests.

## Pattern 2: Plan Before Execution

    Create a step-by-step plan. For each step, list:
    - command or file change
    - purpose
    - risk
    - rollback method

    Do not execute until I approve.

## Pattern 3: Evidence Before Claims

    Before answering, verify with commands or file reads. Show the evidence.

## Pattern 4: Small Diffs

    Produce the smallest possible diff. Do not refactor unrelated code.

## Pattern 5: Explicit Stop Conditions

    Stop and ask if:
    - tests fail
    - linters fail
    - required context is missing
    - a destructive command is needed
    - a dependency upgrade is needed
    - behavior is ambiguous
