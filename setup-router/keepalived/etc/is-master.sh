#!/bin/bash

# Return success only when this node is currently recorded as Keepalived MASTER.
# This is intended for external cron/systemd timers:
#   /bin/bash /path/to/keepalived/etc/is-master.sh && /bin/bash /home/router/update-ddns/update-ddns.sh

set -u

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
STATE_FILE="${KEEPALIVED_STATE_FILE:-$SCRIPT_DIR/state/current.env}"
MAX_AGE="${KEEPALIVED_MASTER_MAX_AGE:-0}"
QUIET=0

function usage() {
  cat <<'EOF'
Usage: is-master.sh [--quiet] [--state-file FILE] [--max-age SECONDS]

Exit codes:
  0  Current state is MASTER.
  1  Current state is not MASTER.
  2  State file is missing, unreadable, or stale.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -q|--quiet)
      QUIET=1
      shift
      ;;
    --state-file)
      STATE_FILE="$2"
      shift 2
      ;;
    --max-age)
      MAX_AGE="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

function read_state_value() {
  local key="$1"

  awk -F= -v key="$key" '$1 == key { print substr($0, index($0, "=") + 1); exit }' "$STATE_FILE" 2>/dev/null
}

if [[ ! -r "$STATE_FILE" ]]; then
  [[ "$QUIET" -eq 1 ]] || echo "UNKNOWN: state file is missing or unreadable: $STATE_FILE" >&2
  exit 2
fi

STATE="$(read_state_value STATE)"
UPDATED_AT_EPOCH="$(read_state_value UPDATED_AT_EPOCH)"

if [[ -n "$MAX_AGE" ]] && [[ "$MAX_AGE" -gt 0 ]] 2>/dev/null; then
  NOW_EPOCH="$(date '+%s' 2>/dev/null || echo 0)"
  if [[ "$UPDATED_AT_EPOCH" =~ ^[0-9]+$ ]] && [[ $((NOW_EPOCH - UPDATED_AT_EPOCH)) -gt "$MAX_AGE" ]]; then
    [[ "$QUIET" -eq 1 ]] || echo "STALE: state file is older than ${MAX_AGE}s: $STATE_FILE" >&2
    exit 2
  fi
fi

if [[ "$STATE" == "MASTER" ]]; then
  [[ "$QUIET" -eq 1 ]] || echo "MASTER"
  exit 0
fi

[[ "$QUIET" -eq 1 ]] || echo "${STATE:-UNKNOWN}"
exit 1