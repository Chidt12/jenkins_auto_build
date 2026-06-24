#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLIST_PATH="$HOME/Library/LaunchAgents/com.jenkins.agent.plist"

# Load .env for workdir path
source "$SCRIPT_DIR/.env"
mkdir -p "$JENKINS_AGENT_WORKDIR/logs"

cat > "$PLIST_PATH" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.jenkins.agent</string>
  <key>ProgramArguments</key>
  <array>
    <string>$SCRIPT_DIR/start-agent.sh</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>StandardOutPath</key>
  <string>$JENKINS_AGENT_WORKDIR/logs/agent.stdout.log</string>
  <key>StandardErrorPath</key>
  <string>$JENKINS_AGENT_WORKDIR/logs/agent.stderr.log</string>
  <key>WorkingDirectory</key>
  <string>$SCRIPT_DIR</string>
</dict>
</plist>
EOF

launchctl load "$PLIST_PATH"
echo "Jenkins agent service installed and started."
echo "Plist: $PLIST_PATH"
echo "Logs:  $JENKINS_AGENT_WORKDIR/logs/"
echo ""
echo "To check status: launchctl list | grep jenkins"
echo "To stop:         ./uninstall-service.sh"
