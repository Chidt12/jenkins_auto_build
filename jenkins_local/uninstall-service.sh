#!/bin/bash

PLIST_PATH="$HOME/Library/LaunchAgents/com.jenkins.agent.plist"

if [ ! -f "$PLIST_PATH" ]; then
  echo "Service not installed."
  exit 0
fi

launchctl unload "$PLIST_PATH"
rm "$PLIST_PATH"
echo "Jenkins agent service uninstalled."
