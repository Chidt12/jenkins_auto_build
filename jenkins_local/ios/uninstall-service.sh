#!/bin/bash

PLIST_PATH="$HOME/Library/LaunchAgents/com.jenkins.agent.plist"

if [ ! -f "$PLIST_PATH" ]; then
  echo "Service not installed."
  exit 0
fi

launchctl bootout "gui/$(id -u)" "$PLIST_PATH" 2>/dev/null || \
launchctl unload "$PLIST_PATH" 2>/dev/null || true
rm -f "$PLIST_PATH"
echo "Jenkins agent service uninstalled."
