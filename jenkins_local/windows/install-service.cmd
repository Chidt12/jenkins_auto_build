@echo off
rem Windows version of install-service.sh. Registers a Scheduled Task that
rem starts the Jenkins agent when this user logs on. A batch loop restarts
rem the agent whenever it exits, like KeepAlive in the macOS plist.
rem
rem Run from Command Prompt in this folder. The script asks for
rem administrator rights through UAC if the prompt does not have them:
rem   install-service
setlocal

set "SCRIPT_DIR=%~dp0"
set "TASK_NAME=JenkinsAgent"

rem Creating a logon task needs administrator rights. Without them, ask
rem through UAC and run this script again in a new administrator window.
net session >nul 2>&1
if errorlevel 1 (
  echo Asking for administrator rights ...
  powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -ArgumentList 'elevated' -Verb RunAs"
  if errorlevel 1 echo ERROR: Administrator rights were not given.
  exit /b
)

rem The administrator window closes when the script ends, so keep it open
rem until the user reads the result
if /i "%~1"=="elevated" (
  call :main
  echo.
  pause
  exit /b
)
call :main
exit /b

:main

rem Load .env, same file as the macOS scripts
if not exist "%SCRIPT_DIR%.env" (
  echo ERROR: .env file not found. Copy .env.example to .env and fill it in.
  exit /b 1
)
for /f "usebackq eol=# tokens=1,* delims==" %%A in ("%SCRIPT_DIR%.env") do set "%%A=%%B"

for %%V in (JENKINS_URL JENKINS_AGENT_NAME JENKINS_AGENT_SECRET JENKINS_AGENT_WORKDIR) do (
  if not defined %%V (
    echo ERROR: %%V not set in .env
    exit /b 1
  )
)
set "JENKINS_URL=%JENKINS_URL:"=%"
set "JENKINS_AGENT_NAME=%JENKINS_AGENT_NAME:"=%"
set "JENKINS_AGENT_SECRET=%JENKINS_AGENT_SECRET:"=%"
set "WORKDIR=%JENKINS_AGENT_WORKDIR:"=%"
if "%JENKINS_URL:~-1%"=="/" set "JENKINS_URL=%JENKINS_URL:~0,-1%"
if "%JENKINS_AGENT_SECRET%"=="<paste-secret-from-jenkins-ui-after-adding-node>" (
  echo ERROR: JENKINS_AGENT_SECRET not set in .env
  echo Get it from: Jenkins - Manage Jenkins - Nodes - %JENKINS_AGENT_NAME%
  exit /b 1
)

rem Connection mode. The first word only, which drops an inline "# ..." comment.
if not defined JENKINS_AGENT_MODE set "JENKINS_AGENT_MODE=direct"
for /f "tokens=1" %%M in ("%JENKINS_AGENT_MODE%") do set "JENKINS_AGENT_MODE=%%M"
set "CONNECTION_ARGS="
if /i "%JENKINS_AGENT_MODE%"=="websocket" set "CONNECTION_ARGS= -webSocket"

rem Resolve java path. The runner bakes in the absolute path so it does not
rem depend on the PATH of the logon session.
set "JAVA_BIN="
for /f "delims=" %%J in ('where java 2^>nul') do if not defined JAVA_BIN set "JAVA_BIN=%%J"
if not defined JAVA_BIN if defined JAVA_HOME if exist "%JAVA_HOME%\bin\java.exe" set "JAVA_BIN=%JAVA_HOME%\bin\java.exe"
if not defined JAVA_BIN (
  echo ERROR: java not found. Install Java 21 with: winget install EclipseAdoptium.Temurin.21.JDK
  echo Then open a new Command Prompt and run install-service again.
  exit /b 1
)

rem Jenkinsfile "sh" steps need sh.exe from Git for Windows. Git puts only
rem git.exe on the PATH, so find Git's bin folder from where git.exe is.
set "GIT_BIN="
for /f "delims=" %%G in ('where git 2^>nul') do if not defined GIT_BIN set "GIT_BIN=%%~dpG..\bin"
if defined GIT_BIN for %%P in ("%GIT_BIN%") do set "GIT_BIN=%%~fP"
if defined GIT_BIN if not exist "%GIT_BIN%\sh.exe" set "GIT_BIN="
if not defined GIT_BIN if exist "%ProgramFiles%\Git\bin\sh.exe" set "GIT_BIN=%ProgramFiles%\Git\bin"
if not defined GIT_BIN (
  echo WARNING: sh.exe from Git for Windows not found. Jenkinsfile "sh" steps fail on this agent.
  echo Run setup first, then run install-service again.
)

rem In "sh" steps, gcloud and gsutil run their shell scripts. These look for
rem python3 on the PATH and find the Microsoft Store alias, which only prints
rem "Python was not found". Point them to the Python in the Cloud SDK.
set "GCLOUD_PYTHON="
for /f "delims=" %%G in ('where gcloud 2^>nul') do if not defined GCLOUD_PYTHON set "GCLOUD_PYTHON=%%~dpG..\platform\bundledpython\python.exe"
if defined GCLOUD_PYTHON for %%P in ("%GCLOUD_PYTHON%") do set "GCLOUD_PYTHON=%%~fP"
if defined GCLOUD_PYTHON if not exist "%GCLOUD_PYTHON%" set "GCLOUD_PYTHON="
if not defined GCLOUD_PYTHON if exist "%LOCALAPPDATA%\Google\Cloud SDK\google-cloud-sdk\platform\bundledpython\python.exe" set "GCLOUD_PYTHON=%LOCALAPPDATA%\Google\Cloud SDK\google-cloud-sdk\platform\bundledpython\python.exe"
if not defined GCLOUD_PYTHON if exist "%ProgramFiles(x86)%\Google\Cloud SDK\google-cloud-sdk\platform\bundledpython\python.exe" set "GCLOUD_PYTHON=%ProgramFiles(x86)%\Google\Cloud SDK\google-cloud-sdk\platform\bundledpython\python.exe"
if not defined GCLOUD_PYTHON (
  echo WARNING: Python of the Google Cloud SDK not found. gcloud and gsutil fail in "sh" steps.
  echo Run setup first, then run install-service again.
)

rem Stop any existing service first. cmd reads a batch file while it runs,
rem so the old runner must exit before we rewrite it.
call "%SCRIPT_DIR%uninstall-service.cmd" quiet
if errorlevel 1 exit /b 1

if not exist "%WORKDIR%\logs" mkdir "%WORKDIR%\logs"

rem agent.jar is not in git. Download it from the controller so its version
rem matches, and fall back to a local copy if the download fails.
set "AGENT_JAR=%WORKDIR%\agent.jar"
echo Downloading agent.jar from %JENKINS_URL% ...
curl.exe -sSfL "%JENKINS_URL%/jnlpJars/agent.jar" -o "%AGENT_JAR%"
if errorlevel 1 (
  if not exist "%SCRIPT_DIR%agent.jar" (
    echo ERROR: Could not download "%JENKINS_URL%/jnlpJars/agent.jar"
    exit /b 1
  )
  echo WARNING: Download of agent.jar failed, using "%SCRIPT_DIR%agent.jar"
  copy /y "%SCRIPT_DIR%agent.jar" "%AGENT_JAR%" >nul
)

rem Generate the runner. It contains the secret, like the macOS plist.
rem uninstall-service.cmd creates agent.stop to end its loop.
set "RUNNER=%WORKDIR%\run-agent.cmd"
set "STOP_FLAG=%WORKDIR%\agent.stop"
set "STDOUT_LOG=%WORKDIR%\logs\agent.stdout.log"
set "STDERR_LOG=%WORKDIR%\logs\agent.stderr.log"
if exist "%STOP_FLAG%" del /q "%STOP_FLAG%"
> "%RUNNER%" (
  echo @echo off
  echo rem Generated by install-service.cmd. Restarts the Jenkins agent whenever it exits.
  echo title Jenkins Agent - do not close
  echo cd /d "%WORKDIR%"
  if defined GIT_BIN echo set "PATH=%GIT_BIN%;%%PATH%%"
  if defined GCLOUD_PYTHON echo set "CLOUDSDK_PYTHON=%GCLOUD_PYTHON%"
  echo :loop
  echo if exist "%STOP_FLAG%" exit
  echo echo [%%DATE%% %%TIME%%] Starting Jenkins agent ^>^> "%STDOUT_LOG%"
  echo "%JAVA_BIN%" -jar "%AGENT_JAR%" -url "%JENKINS_URL%" -secret "%JENKINS_AGENT_SECRET%" -name "%JENKINS_AGENT_NAME%" -workDir "%WORKDIR%"%CONNECTION_ARGS% ^>^> "%STDOUT_LOG%" 2^>^> "%STDERR_LOG%"
  echo if exist "%STOP_FLAG%" exit
  echo echo [%%DATE%% %%TIME%%] Agent exited with code %%ERRORLEVEL%%, restarting in 10 seconds ^>^> "%STDOUT_LOG%"
  echo ping -n 11 127.0.0.1 ^> nul
  echo goto loop
)

rem Run in the user's interactive session, like a macOS LaunchAgent, so Unity
rem has the user profile and license. The runner starts in a minimized window
rem and the task itself ends at once, so the task time limit never applies.
schtasks /create /tn "%TASK_NAME%" /sc onlogon /ru "%USERDOMAIN%\%USERNAME%" /it /rl limited /f /tr "cmd.exe /c start \"Jenkins Agent\" /min \"%RUNNER%\"" >nul
if errorlevel 1 (
  echo ERROR: Could not create the scheduled task.
  exit /b 1
)
schtasks /run /tn "%TASK_NAME%" >nul

echo Jenkins agent service installed and started.
echo Task:   %TASK_NAME%, runs as %USERDOMAIN%\%USERNAME%
echo Runner: "%RUNNER%"
if defined GIT_BIN echo sh:     "%GIT_BIN%\sh.exe"
if defined GCLOUD_PYTHON echo gcloud: "%GCLOUD_PYTHON%"
echo Logs:   "%WORKDIR%\logs"
echo.
echo The agent starts when this user logs on. For an unattended machine, turn on automatic logon.
echo Do not close the minimized "Jenkins Agent" window. Closing it stops the agent.
echo.
echo To check status: schtasks /query /tn %TASK_NAME%
echo To stop:         uninstall-service
