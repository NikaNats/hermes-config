#!/usr/bin/env bash
# Generate the Hermes logrotate config and print the apply command (spec 5.7).
# The agent cannot sudo by policy, so this helper only prepares the file and
# tells the human the exact command to run. Usage: bash scripts/setup-logrotate.sh
set -Eeuo pipefail
IFS=$'\n\t'

# Hermes' canonical default home is ~/.hermes (hermes_constants.py
# _get_platform_default_hermes_home); HERMES_HOME overrides it when set.
HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
# R-14: temp file out of /tmp (no sticky-dir exposure) under $HOME, and the
# path is QUOTED inside the logrotate stanza so spaces/specials cannot break
# or inject into the config. No EXIT trap: the file must survive for the human
# to install (the apply command below references it).
LOGROTATE_FILE="$(mktemp "${HOME}/hermes-logrotate.XXXXXX")"
printf '%s/logs/*.log {\n  weekly\n  rotate 8\n  compress\n  delaycompress\n  missingok\n  notifempty\n}\n' \
  "\"$HERMES_HOME\"" > "$LOGROTATE_FILE"

echo "Generated $LOGROTATE_FILE"
echo "Checksum: $(sha256sum "$LOGROTATE_FILE")"
echo
echo "To apply, run (you, not the agent):"
echo "  sudo install -m 0644 $LOGROTATE_FILE /etc/logrotate.d/hermes"
echo "  sudo logrotate -d /etc/logrotate.d/hermes   # dry-run to verify"
