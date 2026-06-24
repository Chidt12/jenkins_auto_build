# Jenkins Build Infrastructure

Auto-build pipeline for Unity projects (Android + iOS).

- **jenkins_server/** — Docker-based Jenkins server (runs on your cloud server)
- **jenkins_local/** — Jenkins agent scripts (runs on your Mac Mini build machine)

---

## Part 1: Jenkins Server Setup (Cloud)

### 1.1 Configure

```bash
cd jenkins_server
cp .env.example .env
```

Edit `.env` with your values:

```env
JENKINS_HTTP_PORT=9090          # pick any available port
JENKINS_AGENT_PORT=50000        # agent connection port
JENKINS_ADMIN_USER=admin        # your admin username
JENKINS_ADMIN_PASSWORD=<strong_password>
JENKINS_URL=http://your-server-ip:9090   # URL agents/browsers use to reach Jenkins
```

### 1.2 Start Jenkins

```bash
cd jenkins_server
docker compose up -d --build
```

First build takes ~2 minutes (downloads plugins). Check logs:

```bash
docker compose logs -f jenkins
```

Wait until you see: `Jenkins is fully up and running`

### 1.3 Verify

Open browser: `http://your-server-ip:9090`

- No setup wizard — goes straight to login
- Login with the credentials from `.env`
- You should see: "BaldEagle Hub — Jenkins Build Server"

### 1.4 Useful commands

```bash
# Stop Jenkins
docker compose down

# Restart Jenkins
docker compose restart

# View logs
docker compose logs -f jenkins

# Rebuild after changing Dockerfile/plugins
docker compose up -d --build

# Reset everything (deletes all Jenkins data!)
docker compose down -v
```

---

## Part 2: Mac Mini Setup (Build Machine)

### 2.1 Hardware

1. Plug in an **HDMI dummy plug** (~$5) — prevents GPU issues during Unity builds
2. Connect to network (**Ethernet preferred** for stability)

### 2.2 macOS Settings

Open **System Settings** and configure:

| Setting | Where | Value |
|---------|-------|-------|
| Remote Login (SSH) | General → Sharing → Remote Login | **ON** |
| Automatic Login | Users & Groups → Automatic Login | **Your user** |
| Turn display off | Energy → Turn display off | **Never** |
| Prevent sleeping | Energy → Prevent automatic sleeping | **ON** |
| Wake for network | Energy → Wake for network access | **ON** |
| Lock Screen | Lock Screen → Require password | **OFF** |

### 2.3 Install Required Software

```bash
# Xcode (install from App Store first, then run:)
sudo xcode-select --install
sudo xcodebuild -license accept

# Java 21 (required for Jenkins agent — must match server JDK version)
brew install openjdk@21
sudo ln -sfn $(brew --prefix)/opt/openjdk@21/libexec/openjdk.jdk /Library/Java/JavaVirtualMachines/openjdk-21.jdk

# Fastlane (for store uploads)
brew install fastlane

# CocoaPods (for iOS dependencies)
sudo gem install cocoapods

# Unity Hub + Unity
# Install Unity Hub from https://unity.com/download
# Then install Unity 2022.3.x with iOS + Android build support modules
```

### 2.4 Activate Unity License

Unity Personal requires manual activation (one-time):

1. Open Unity Hub on the Mac Mini
2. Sign in with your Unity account
3. Open any project — Unity activates automatically
4. Done — CLI/headless builds will work from now on
5. **Important:** Unity Personal allows only one machine per account — use a dedicated CI account so it doesn't conflict with your dev machine

---

## Part 3: Connect Agent to Server

### 3.1 Add Node in Jenkins UI

1. Open Jenkins: `http://your-server-ip:9090`
2. Go to: **Manage Jenkins → Nodes → New Node**
3. Fill in:
   - **Node name:** `mac-builder`
   - **Type:** Permanent Agent
4. Click **Create**, then configure:
   - **Remote root directory:** `/Users/your-user/jenkins-agent`
   - **Labels:** `mac unity ios android`
   - **Usage:** Only build jobs with label expressions matching this node
   - **Launch method:** Launch agent by connecting it to the controller
5. Click **Save**
6. Click on the new `mac-builder` node → **copy the secret** shown on the page

### 3.2 Configure Agent on Mac

```bash
cd jenkins_local
cp .env.example .env
```

Edit `.env`:

```env
JENKINS_URL=http://your-server-ip:9090
JENKINS_AGENT_NAME=mac-builder
JENKINS_AGENT_SECRET=<paste-the-secret-from-step-3.1>
JENKINS_AGENT_WORKDIR=/Users/your-user/jenkins-agent
UNITY_EDITORS_PATH=/Applications/Unity/Hub/Editor
```

### 3.3 Run Setup

```bash
cd jenkins_local
./setup.sh
```

This will:
- Check Java is installed
- Create the work directory
- Download `agent.jar` from your Jenkins server
- Detect installed Unity versions, Xcode, Fastlane
- Print next steps

### 3.4 Start Agent

```bash
./start-agent.sh
```

You should see: `Connected` in the terminal.

Verify in Jenkins UI: **Manage Jenkins → Nodes** — `mac-builder` should show a **green circle** (online).

### 3.5 Test the Connection

In Jenkins UI:
1. **New Item** → Pipeline → name it `test-connection`
2. Paste this pipeline script:

```groovy
pipeline {
    agent { label 'mac' }
    stages {
        stage('Test') {
            steps {
                sh 'echo "Hello from $(hostname)"'
                sh 'sw_vers'
                sh 'java -version'
                sh 'ls /Applications/Unity/Hub/Editor/ 2>/dev/null || echo "No Unity found"'
                sh 'xcodebuild -version 2>/dev/null || echo "No Xcode found"'
                sh 'fastlane --version 2>/dev/null || echo "No Fastlane found"'
            }
        }
    }
}
```

3. Click **Build Now**
4. Check **Console Output** — should show Mac info, Unity versions, Xcode, etc.

### 3.6 Auto-Start Agent on Boot (Optional)

So the agent starts automatically when the Mac boots:

```bash
./install-service.sh
```

To check it's running:
```bash
launchctl list | grep jenkins
```

To remove auto-start:
```bash
./uninstall-service.sh
```

---

## Troubleshooting

| Problem | Solution |
|---------|----------|
| `docker compose up` fails | Check Docker is running. Check port isn't already in use: `lsof -i :9090` |
| Can't login to Jenkins | Check credentials in `.env`. Reset: `docker compose down -v && docker compose up -d --build` |
| Agent won't connect | Check `JENKINS_URL` is reachable from Mac: `curl -I http://your-server:9090`. Check `JENKINS_AGENT_SECRET` matches. |
| Agent connects then disconnects | Check Java version: `java -version` (need 17+). Check firewall isn't blocking outbound. |
| Unity not detected | Verify path: `ls /Applications/Unity/Hub/Editor/`. Install via Unity Hub with iOS + Android modules. |
| `setup.sh` can't download agent.jar | Jenkins server must be running. Check URL: `curl http://your-server:9090/jnlpJars/agent.jar -o /dev/null` |
| Agent logs | Check `$JENKINS_AGENT_WORKDIR/logs/agent.stdout.log` and `agent.stderr.log` |
