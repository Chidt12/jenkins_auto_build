#!/bin/bash

PID=$(pgrep -f "agent.jar.*-name")

if [ -z "$PID" ]; then
  echo "Jenkins agent is not running."
  exit 0
fi

echo "Stopping Jenkins agent (PID: $PID)..."
kill "$PID"
echo "Agent stopped."
