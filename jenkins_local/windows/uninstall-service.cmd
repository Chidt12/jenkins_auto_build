@echo off
rem Windows version of uninstall-service.sh.
rem
rem Run from Command Prompt in this folder. The script asks for
rem administrator rights through UAC if the prompt does not have them:
rem   uninstall-service
setlocal

set "SCRIPT_DIR=%~dp0"
set "TASK_NAME=JenkinsAgent"
rem install-service.cmd passes "quiet" when it stops an existing service
set "QUIET=%~1"

rem Deleting the logon task needs administrator rights. Without them, ask
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

schtasks /query /tn "%TASK_NAME%" >nul 2>&1
if errorlevel 1 (
  if not "%QUIET%"=="quiet" echo Service not installed.
  exit /b 0
)

echo Stopping Jenkins agent ...

rem The work directory holds the runner and its stop flag
set "WORKDIR="
if exist "%SCRIPT_DIR%.env" (
  for /f "usebackq eol=# tokens=1,* delims==" %%A in ("%SCRIPT_DIR%.env") do set "%%A=%%B"
)
if defined JENKINS_AGENT_WORKDIR set "WORKDIR=%JENKINS_AGENT_WORKDIR:"=%"

rem The runner checks for agent.stop each time the agent exits, so create
rem it before ending the agent
if defined WORKDIR (
  echo stop> "%WORKDIR%\agent.stop"
) else (
  echo WARNING: JENKINS_AGENT_WORKDIR not found in .env. The runner window may restart the agent. Close it by hand.
)

schtasks /end /tn "%TASK_NAME%" >nul 2>&1
schtasks /delete /tn "%TASK_NAME%" /f >nul

rem jps comes with the JDK and lists Java processes with the jar they run.
rem It finds the agent without stopping other Java processes such as Gradle.
set "JPS="
for /f "delims=" %%J in ('where java 2^>nul') do if not defined JPS if exist "%%~dpJjps.exe" set "JPS=%%~dpJjps.exe"
if not defined JPS if defined JAVA_HOME if exist "%JAVA_HOME%\bin\jps.exe" set "JPS=%JAVA_HOME%\bin\jps.exe"
if not defined JPS for /f "delims=" %%J in ('where jps 2^>nul') do if not defined JPS set "JPS=%%J"
if not defined JPS echo WARNING: jps not found. If the node is still online in Jenkins, end java.exe in Task Manager.
if defined JPS "%JPS%" -l | findstr /i /c:"agent.jar" > "%TEMP%\jenkins-agent-pids.txt"
if exist "%TEMP%\jenkins-agent-pids.txt" (
  for /f "usebackq tokens=1" %%P in ("%TEMP%\jenkins-agent-pids.txt") do taskkill /f /pid %%P >nul 2>&1
  del /q "%TEMP%\jenkins-agent-pids.txt"
)

rem Give the runner time to see agent.stop and exit. It waits 10 seconds
rem between restarts.
ping -n 13 127.0.0.1 >nul

if defined WORKDIR (
  del /q "%WORKDIR%\run-agent.cmd" 2>nul
  del /q "%WORKDIR%\agent.stop" 2>nul
)
if not "%QUIET%"=="quiet" echo Jenkins agent service uninstalled.
exit /b 0
