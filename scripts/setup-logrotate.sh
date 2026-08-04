#!/usr/bin/env bash
# Generate the Hermes logrotate config and print the apply command (spec 5.7).
# The agent cannot sudo by policy, so this helper only prepares the file and
# tells the human the exact command to run. Usage: bash scripts/setup-logrotate.sh
set -Eeuo pipefail
IFS=$'\n\t'

LOGROTATE_FILE="/tmp/hermes-logrotate"
HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
cat > "$LOGROTATE_FILE" <<EOF
$HERMES_HOME/logs/*.log {
    weekly
    rotate 8
    compress
    delaycompress
    missingok
    notifempty
}
EOF

echo "Generated $LOGROTATE_FILE"
echo
echo "To apply, run (you, not the agent):"
echo "  sudo install -m 0644 $LOGROTATE_FILE /etc/logrotate.d/hermes"
echo "  sudo logrotate -d /etc/logrotate.d/hermes   # dry-run to verify"
