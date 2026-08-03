# Reporting & Knowledge Artifacts (spec 4.5)

Standard artifact directory (already created on this machine):

    ~/agent/reports/YYYY-MM-DD/

## Naming examples

    ~/agent/reports/2026-06-17/log-analysis-nginx.md
    ~/agent/reports/2026-06-17/dependency-upgrade-plan.md
    ~/agent/reports/2026-06-17/incident-summary.md

## Creating a report

Use the helper (creates the dated dir + copies the template):

    scripts/new-report.sh <name>
    # -> prints the created file path, e.g. ~/agent/reports/2026-08-03/<name>.md

or manually:

    mkdir -p ~/agent/reports/"$(date +%Y-%m-%d)"

## Template

Reports default to Markdown (template at `scripts/templates/report.md`):

    # Title

    ## Summary

    ## Evidence

    ## Findings

    ## Risks

    ## Recommended Actions

    ## Follow-up Commands
