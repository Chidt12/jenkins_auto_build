#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLIST_PATH="$HOME/Library/LaunchAgents/com.jenkins.agent.plist"

# Load .env for workdir path
source "$SCRIPT_DIR/.env"
mkdir -p "$JENKINS_AGENT_WORKDIR/logs"

# Copy agent.jar to the workdir so the plist doesn't need to access
# ~/Desktop (which requires Full Disk Access under macOS)
cp "$SCRIPT_DIR/agent.jar" "$JENKINS_AGENT_WORKDIR/agent.jar"

# Resolve java path — launchd uses a minimal PATH that won't find
# Homebrew/Temurin installs, so we bake in the absolute path
JAVA_BIN="$(command -v java)"
if [ -z "$JAVA_BIN" ]; then
  echo "ERROR: java not found. Run ./setup.sh first."
  exit 1
fi

# Connection mode
AGENT_MODE="${JENKINS_AGENT_MODE:-direct}"
CONNECTION_ARGS=""
if [ "$AGENT_MODE" = "websocket" ]; then
  CONNECTION_ARGS="<string>-webSocket</string>"
fi

cat > "$PLIST_PATH" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.jenkins.agent</string>
  <key>ProgramArguments</key>
  <array>
    <string>$JAVA_BIN</string>
    <string>-jar</string>
    <string>$JENKINS_AGENT_WORKDIR/agent.jar</string>
    <string>-url</string>
    <string>$JENKINS_URL</string>
    <string>-secret</string>
    <string>$JENKINS_AGENT_SECRET</string>
    <string>-name</string>
    <string>$JENKINS_AGENT_NAME</string>
    <string>-workDir</string>
    <string>$JENKINS_AGENT_WORKDIR</string>
    $CONNECTION_ARGS
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
  <string>$JENKINS_AGENT_WORKDIR</string>
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
