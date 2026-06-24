#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Load .env
if [ ! -f "$SCRIPT_DIR/.env" ]; then
  echo "ERROR: .env file not found. Copy .env.example to .env and fill in the values."
  exit 1
fi
source "$SCRIPT_DIR/.env"

echo "=== Jenkins Agent Setup ==="
echo ""

# Check Java
if ! command -v java &>/dev/null; then
  echo "ERROR: Java is not installed."
  echo "Install with: brew install openjdk@17"
  exit 1
fi
echo "[OK] Java: $(java -version 2>&1 | head -1)"

# Create work directory
mkdir -p "$JENKINS_AGENT_WORKDIR"
mkdir -p "$JENKINS_AGENT_WORKDIR/logs"
echo "[OK] Work directory: $JENKINS_AGENT_WORKDIR"

# Download agent.jar
echo "Downloading agent.jar from $JENKINS_URL ..."
curl -sSfL "$JENKINS_URL/jnlpJars/agent.jar" -o "$SCRIPT_DIR/agent.jar"
echo "[OK] agent.jar downloaded"

# Detect Unity versions
echo ""
echo "=== Detected Unity Versions ==="
if [ -d "$UNITY_EDITORS_PATH" ]; then
  for dir in "$UNITY_EDITORS_PATH"/*/; do
    version=$(basename "$dir")
    echo "  - $version ($dir)"
  done
else
  echo "  No Unity editors found at $UNITY_EDITORS_PATH"
fi

# Check Xcode
echo ""
echo "=== Build Tools ==="
if command -v xcodebuild &>/dev/null; then
  echo "[OK] Xcode: $(xcodebuild -version | head -1)"
else
  echo "[--] Xcode: not installed"
fi

if command -v fastlane &>/dev/null; then
  echo "[OK] Fastlane: $(fastlane --version 2>&1 | head -1)"
else
  echo "[--] Fastlane: not installed (brew install fastlane)"
fi

if command -v pod &>/dev/null; then
  echo "[OK] CocoaPods: $(pod --version)"
else
  echo "[--] CocoaPods: not installed (sudo gem install cocoapods)"
fi

echo ""
echo "=== Next Steps ==="
echo "1. In Jenkins UI: Manage Jenkins → Nodes → New Node"
echo "   - Name: $JENKINS_AGENT_NAME"
echo "   - Type: Permanent Agent"
echo "   - Remote root directory: $JENKINS_AGENT_WORKDIR"
echo "   - Launch method: Launch agent by connecting it to the controller"
echo "2. Copy the secret from the node page and paste it into .env as JENKINS_AGENT_SECRET"
echo "3. Run: ./start-agent.sh"
echo ""
