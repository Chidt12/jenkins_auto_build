@echo off
rem Windows version of setup.sh. Checks the build tools and installs the
rem missing ones with winget. Xcode, CocoaPods and PyJWT are iOS only, so
rem they are not part of this script.
rem
rem Run from Command Prompt in this folder:
rem   setup
setlocal

set "SCRIPT_DIR=%~dp0"

rem Load .env, same format as the macOS scripts
if not exist "%SCRIPT_DIR%.env" (
  echo ERROR: .env file not found. Copy .env.example to .env and fill in the values.
  exit /b 1
)
for /f "usebackq eol=# tokens=1,* delims==" %%A in ("%SCRIPT_DIR%.env") do set "%%A=%%B"
if not defined JENKINS_AGENT_WORKDIR (
  echo ERROR: JENKINS_AGENT_WORKDIR not set in .env
  exit /b 1
)
set "WORKDIR=%JENKINS_AGENT_WORKDIR:"=%"
if not defined UNITY_EDITORS_PATH set "UNITY_EDITORS_PATH=C:\Program Files\Unity\Hub\Editor"
set "UNITY_EDITORS_PATH=%UNITY_EDITORS_PATH:"=%"

where winget >nul 2>&1
if errorlevel 1 (
  echo ERROR: winget not found. Install "App Installer" from the Microsoft Store, then run setup again.
  exit /b 1
)
set "WINGET=winget install -e --silent --accept-package-agreements --accept-source-agreements --id"
rem A tool installed now is not on the PATH of this window
set "NEED_NEW_TERMINAL="

echo === Jenkins Agent Setup ===
echo.

rem Java. The controller runs JDK 21, so install the same version.
java -version >nul 2>&1
if errorlevel 1 (
  echo [INSTALL] Java 21 - Temurin JDK ...
  %WINGET% EclipseAdoptium.Temurin.21.JDK
  set "NEED_NEW_TERMINAL=1"
) else (
  for /f "delims=" %%V in ('java -version 2^>^&1 ^| findstr /i "version"') do echo [OK] Java: %%V
)

rem Work directory
if not exist "%WORKDIR%\logs" mkdir "%WORKDIR%\logs"
echo [OK] Work directory: "%WORKDIR%"

rem Detect Unity versions
echo.
echo === Detected Unity Versions ===
if exist "%UNITY_EDITORS_PATH%" (
  for /d %%D in ("%UNITY_EDITORS_PATH%\*") do echo   - %%~nxD
) else (
  echo   No Unity editors found at "%UNITY_EDITORS_PATH%"
)

echo.
echo === Build Tools ===

rem Git for Windows. It also includes sh.exe for Jenkinsfile "sh" steps.
git --version >nul 2>&1
if errorlevel 1 (
  echo [INSTALL] Git for Windows ...
  %WINGET% Git.Git
  set "NEED_NEW_TERMINAL=1"
) else (
  for /f "delims=" %%V in ('git --version') do echo [OK] Git: %%V
)

rem Git puts git.exe on the PATH, but not sh.exe
where sh >nul 2>&1
if errorlevel 1 (
  echo [--] sh: not on the PATH. Jenkinsfile "sh" steps fail on this agent.
  echo      Add C:\Program Files\Git\bin to the system PATH, or use "bat" steps.
) else (
  echo [OK] sh: found
)

rem fastlane (Google Play upload). It is a Ruby gem, so Ruby comes first.
where fastlane >nul 2>&1
if not errorlevel 1 (
  echo [OK] fastlane: installed
) else (
  where gem >nul 2>&1
  if errorlevel 1 (
    echo [INSTALL] Ruby, needed for fastlane ...
    %WINGET% RubyInstallerTeam.RubyWithDevKit.3.3
    echo [--] fastlane: open a new Command Prompt and run setup again to install it
    set "NEED_NEW_TERMINAL=1"
  ) else (
    echo [INSTALL] fastlane ...
    call gem install fastlane --no-document
    echo [OK] fastlane installed
  )
)

rem rclone (Google Drive upload)
where rclone >nul 2>&1
if errorlevel 1 (
  echo [INSTALL] rclone ...
  %WINGET% Rclone.Rclone
  set "NEED_NEW_TERMINAL=1"
) else (
  for /f "delims=" %%V in ('rclone version ^| findstr /b "rclone"') do echo [OK] rclone: %%V
)

rem gsutil (Firebase Storage upload)
where gsutil >nul 2>&1
if errorlevel 1 (
  echo [INSTALL] Google Cloud SDK, includes gsutil ...
  %WINGET% Google.CloudSDK
  set "NEED_NEW_TERMINAL=1"
) else (
  echo [OK] gsutil: installed
)

echo.
echo === Jenkins Credentials ===
echo Android jobs use GPLAY_SERVICE_ACCOUNT_JSON, GDRIVE_SERVICE_ACCOUNT_JSON and
echo FIREBASE_SERVICE_ACCOUNT_JSON. They are on the Jenkins server, see README Part 4.

echo.
echo === Next Steps ===
if defined NEED_NEW_TERMINAL (
  echo 0. Some tools were installed now. Open a new Command Prompt and run setup again.
)
echo 1. In Jenkins UI: Manage Jenkins ^> Nodes ^> New Node
echo    - Name: %JENKINS_AGENT_NAME%
echo    - Type: Permanent Agent
echo    - Remote root directory: %WORKDIR%
echo    - Labels: windows unity android
echo    - Launch method: Launch agent by connecting it to the controller
echo 2. Copy the secret from the node page and paste it into .env as JENKINS_AGENT_SECRET
echo 3. Open Command Prompt as administrator in this folder and run: install-service
echo.
