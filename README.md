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

Install **Xcode** from the App Store first, then accept the license:

```bash
sudo xcodebuild -license accept
```

Install **Unity Hub** from https://unity.com/download, then install Unity with iOS + Android build support modules.

Run `setup.sh` to auto-install everything else (Java, CocoaPods, fastlane, rclone, gsutil, PyJWT, Xcode CLI Tools):

```bash
cd jenkins_local
./setup.sh
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
JENKINS_URL=https://your-jenkins.example.com
JENKINS_AGENT_NAME=mac-builder
JENKINS_AGENT_SECRET=<paste-the-secret-from-step-3.1>
JENKINS_AGENT_WORKDIR=/Users/your-user/jenkins-agent
JENKINS_AGENT_MODE=direct           # 'direct' (port 50000, faster) or 'websocket' (through reverse proxy)
UNITY_EDITORS_PATH=/Applications/Unity/Hub/Editor
```

> **Performance tip:** Use `direct` mode if port 50000 on the Jenkins server is reachable from the Mac. WebSocket mode tunnels through nginx and is significantly slower for log streaming. To enable direct mode:
> 1. On the Jenkins server, open port 50000 in the firewall (`sudo ufw allow 50000/tcp`) and in your cloud provider's firewall (e.g. Hetzner Cloud).
> 2. In Jenkins UI: **Manage Jenkins → Security → TCP port for inbound agents → Fixed: 50000**.

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

## Part 4: Jenkins Credentials (for uploads)

Go to **Manage Jenkins → Credentials → System → Global credentials → Add Credentials**.

### 4.1 iOS TestFlight

Create an API key at [App Store Connect → Users and Access → Integrations → App Store Connect API](https://appstoreconnect.apple.com/access/integrations/api) with **Developer** role (minimum).

| Credential ID | Type | Value |
|---|---|---|
| `ASC_API_KEY_ID` | Secret text | API Key ID (e.g. `ABC123DEFG`) |
| `ASC_API_ISSUER_ID` | Secret text | Issuer ID shown at top of the API keys page |
| `ASC_API_KEY_FILE` | Secret file | `AuthKey_XXXXXXXX.p8` file (downloaded once when creating the key) |

### 4.2 Google Play

| Credential ID | Type | Value |
|---|---|---|
| `GPLAY_SERVICE_ACCOUNT_JSON` | Secret file | Service account JSON key |

Setup steps:
1. [Google Cloud Console](https://console.cloud.google.com) → select or create a project
2. Enable **Google Play Android Developer API**
3. Go to **IAM & Admin → Service Accounts** → Create Service Account → download JSON key
4. [Google Play Console](https://play.google.com/console) → **Setup → API access** → Link your Cloud project
5. Find the service account → Grant **"Release apps to testing tracks"** permission
6. Wait 24-48h for permissions to propagate

### 4.3 Google Drive (Shared Drive)

| Credential ID | Type | Value |
|---|---|---|
| `GDRIVE_SERVICE_ACCOUNT_JSON` | Secret file | Service account JSON key |

> **Note:** Service accounts have no storage quota on personal Google Drive. You must use a **Shared Drive** (Team Drive).

Setup steps:
1. Same Google Cloud project → enable **Google Drive API**
2. Create a service account (or reuse the one from 4.2) → download JSON key
3. Add the JSON key as `GDRIVE_SERVICE_ACCOUNT_JSON` in Jenkins Credentials
4. In Google Drive → **Shared drives** → click **+ New** → create a Shared Drive (e.g. `CI Builds`)
5. Click the **Manage members** icon → add the service account email (e.g. `mybot@project.iam.gserviceaccount.com`) as **Content manager**
6. Copy the Shared Drive ID from the URL: `drive.google.com/drive/folders/<SHARED_DRIVE_ID>`
7. Update `GDRIVE_TEAM_DRIVE_ID` in `Jenkinsfile` environment block with this ID

### 4.4 Firebase Storage (Addressable bundles)

| Credential ID | Type | Value |
|---|---|---|
| `FIREBASE_SERVICE_ACCOUNT_JSON` | Secret file | Service account JSON key with Storage Admin role |

Setup steps:
1. Same Google Cloud project (`idle-zombie-unimob`) → **IAM & Admin → Service Accounts**
2. Create a service account (or reuse existing) → grant **Storage Admin** role (`roles/storage.admin`)
3. Download JSON key and add as `FIREBASE_SERVICE_ACCOUNT_JSON` in Jenkins Credentials
4. Bundles are uploaded to `gs://idle-zombie-unimob.firebasestorage.app/{Android,iOS}/` to match the Addressable remote load path

### 4.5 Git (already configured)

| Credential ID | Type |
|---|---|
| `38369d68-b956-4a87-bac8-f708fedd2dba` | Username/Password for GitLab |

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
