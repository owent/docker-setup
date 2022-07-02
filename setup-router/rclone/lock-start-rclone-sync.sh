#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

CHECK_RUNNING_PID=0
if [[ -e "$SCRIPT_DIR/pidfile" ]]; then
  CHECK_RUNNING_PID=$(cat $SCRIPT_DIR/pidfile)
fi

if [[ $CHECK_RUNNING_PID -gt 0 ]] && [[ -e "/proc/$CHECK_RUNNING_PID/exe" ]]; then
  echo "============ Previous sync ($CHECK_RUNNING_PID) is running, skip this time ============"
  exit 0
fi

echo "============ Start to sync from onedrive ... ============"

/bin/bash $SCRIPT_DIR/start-rclone-sync.sh &

CHECK_RUNNING_PID=$!

echo "$CHECK_RUNNING_PID" >"$SCRIPT_DIR/pidfile"

wait $CHECK_RUNNING_PID
