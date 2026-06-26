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

# Java
if ! command -v java &>/dev/null; then
  echo "[INSTALL] Java ..."
  brew install java
  sudo ln -sfn "$(brew --prefix java)/libexec/openjdk.jdk" /Library/Java/JavaVirtualMachines/openjdk.jdk
  echo "[OK] Java installed"
else
  echo "[OK] Java: $(java -version 2>&1 | head -1)"
fi

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
  echo "[--] Xcode: not installed (install from App Store)"
fi

# Xcode Command Line Tools
if xcode-select -p &>/dev/null; then
  echo "[OK] Xcode CLI Tools: $(xcode-select -p)"
else
  echo "[INSTALL] Xcode Command Line Tools ..."
  xcode-select --install
fi

# CocoaPods
if command -v pod &>/dev/null; then
  echo "[OK] CocoaPods: $(pod --version)"
else
  echo "[INSTALL] CocoaPods ..."
  brew install cocoapods
  echo "[OK] CocoaPods installed"
fi

# fastlane (Google Play upload)
if command -v fastlane &>/dev/null; then
  echo "[OK] fastlane: $(fastlane --version 2>&1 | head -1)"
else
  echo "[INSTALL] fastlane ..."
  brew install fastlane
  echo "[OK] fastlane installed"
fi

# rclone (Google Drive upload)
if command -v rclone &>/dev/null; then
  echo "[OK] rclone: $(rclone --version 2>&1 | head -1)"
else
  echo "[INSTALL] rclone ..."
  brew install rclone
  echo "[OK] rclone installed"
fi

# gsutil (Firebase Storage upload)
if command -v gsutil &>/dev/null; then
  echo "[OK] gsutil: $(gsutil --version 2>&1 | head -1)"
else
  echo "[INSTALL] Google Cloud SDK (includes gsutil) ..."
  brew install google-cloud-sdk
  echo "[OK] gsutil installed"
fi

# PyJWT + cryptography (App Store Connect API validation)
if python3 -c "import jwt" &>/dev/null; then
  echo "[OK] PyJWT: $(python3 -c 'import jwt; print(jwt.__version__)')"
else
  echo "[INSTALL] PyJWT + cryptography ..."
  python3 -m pip install --user PyJWT cryptography -q
  echo "[OK] PyJWT installed"
fi

echo ""
echo "=== Jenkins Credentials ==="
echo "Add these in Jenkins > Manage Jenkins > Credentials:"
echo ""
echo "  iOS TestFlight (role: Developer minimum):"
echo "    - ASC_API_KEY_ID       (Secret text) — API Key ID"
echo "    - ASC_API_ISSUER_ID    (Secret text) — Issuer ID"
echo "    - ASC_API_KEY_FILE     (Secret file) — AuthKey_XXXX.p8"
echo "    Create at: App Store Connect > Users and Access > Integrations > App Store Connect API"
echo ""
echo "  Google Play (permission: 'Release apps to testing tracks' minimum):"
echo "    - GPLAY_SERVICE_ACCOUNT_JSON  (Secret file) — service account JSON key"
echo "    Setup: Cloud Console > enable 'Google Play Android Developer API'"
echo "           > create service account > download JSON key"
echo "           > Play Console > Setup > API access > link project > invite service account"
echo "    Note: permissions may take 24-48h to propagate"
echo ""
echo "  Google Drive (must use a Shared Drive — service accounts have no personal Drive quota):"
echo "    - GDRIVE_SERVICE_ACCOUNT_JSON (Secret file) — service account JSON key"
echo "    Setup: Cloud Console > enable 'Google Drive API'"
echo "           > create service account > download JSON key"
echo "           > Google Drive > Shared drives > create a Shared Drive"
echo "           > add service account email as Content manager"
echo "           > update GDRIVE_TEAM_DRIVE_ID in Jenkinsfile"
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
