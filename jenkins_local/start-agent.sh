#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Load .env
if [ ! -f "$SCRIPT_DIR/.env" ]; then
  echo "ERROR: .env file not found."
  exit 1
fi
source "$SCRIPT_DIR/.env"

if [ ! -f "$SCRIPT_DIR/agent.jar" ]; then
  echo "ERROR: agent.jar not found. Run ./setup.sh first."
  exit 1
fi

if [ -z "$JENKINS_AGENT_SECRET" ] || [ "$JENKINS_AGENT_SECRET" = "<paste-secret-from-jenkins-ui-after-adding-node>" ]; then
  echo "ERROR: JENKINS_AGENT_SECRET not set in .env"
  echo "Get it from: Jenkins → Manage Jenkins → Nodes → $JENKINS_AGENT_NAME"
  exit 1
fi

echo "Starting Jenkins agent '$JENKINS_AGENT_NAME'..."
echo "Connecting to: $JENKINS_URL"
echo "Work directory: $JENKINS_AGENT_WORKDIR"
echo ""

# Connection mode: 'direct' (port 50000, faster) or 'websocket' (through reverse proxy, slower)
AGENT_MODE="${JENKINS_AGENT_MODE:-direct}"

CONNECTION_ARGS=()
if [ "$AGENT_MODE" = "websocket" ]; then
  echo "Mode: WebSocket (through reverse proxy)"
  CONNECTION_ARGS+=(-webSocket)
else
  echo "Mode: Direct JNLP (port 50000) — make sure the port is open on the Jenkins server firewall"
fi

java -jar "$SCRIPT_DIR/agent.jar" \
  -url "$JENKINS_URL" \
  -secret "$JENKINS_AGENT_SECRET" \
  -name "$JENKINS_AGENT_NAME" \
  -workDir "$JENKINS_AGENT_WORKDIR" \
  "${CONNECTION_ARGS[@]}"
