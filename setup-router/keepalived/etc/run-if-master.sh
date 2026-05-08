#!/bin/bash

# Run commands only when Keepalived state is MASTER.
#
# Examples:
#   /bin/bash /etc/keepalived/run-if-master.sh -- /bin/bash /home/router/update-ddns/update-ddns.sh
#   KEEPALIVED_MASTER_DDNS_CMD='/bin/bash /home/router/update-ddns/update-ddns.sh' \
#   KEEPALIVED_MASTER_SSL_SYNC_CMD='/bin/bash /home/router/acme.sh/acme-remote-deploy.sh' \
#     /bin/bash /etc/keepalived/run-if-master.sh

set -u

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
IS_MASTER_SCRIPT="$SCRIPT_DIR/is-master.sh"
STATE_FILE="${KEEPALIVED_STATE_FILE:-$SCRIPT_DIR/state/current.env}"
MAX_AGE="${KEEPALIVED_MASTER_MAX_AGE:-0}"
QUIET=0
COMMAND=()

function usage() {
  cat <<'EOF'
Usage: run-if-master.sh [--quiet] [--state-file FILE] [--max-age SECONDS] [-- COMMAND...]

If COMMAND is provided, it is executed only on MASTER.
If COMMAND is omitted, these optional environment commands are run when set:
  KEEPALIVED_MASTER_DDNS_CMD
  KEEPALIVED_MASTER_SSL_SYNC_CMD

When the node is not MASTER, this script exits 0 after skipping work so timers do not fail.
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
    --)
      shift
      COMMAND=("$@")
      break
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      COMMAND=("$@")
      break
      ;;
  esac
done

IS_MASTER_ARGS=(--quiet --state-file "$STATE_FILE")
if [[ -n "$MAX_AGE" ]] && [[ "$MAX_AGE" -gt 0 ]] 2>/dev/null; then
  IS_MASTER_ARGS+=(--max-age "$MAX_AGE")
fi

if ! /bin/bash "$IS_MASTER_SCRIPT" "${IS_MASTER_ARGS[@]}"; then
  [[ "$QUIET" -eq 1 ]] || echo "Keepalived is not MASTER, skip master-only tasks."
  exit 0
fi

if [[ ${#COMMAND[@]} -gt 0 ]]; then
  [[ "$QUIET" -eq 1 ]] || echo "Keepalived is MASTER, run: ${COMMAND[*]}"
  exec "${COMMAND[@]}"
fi

EXIT_CODE=0
RAN_TASK=0

function run_env_command() {
  local label="$1"
  local command="$2"

  if [[ -z "$command" ]]; then
    return 0
  fi

  RAN_TASK=1
  [[ "$QUIET" -eq 1 ]] || echo "Keepalived is MASTER, run $label: $command"
  bash -lc "$command" || EXIT_CODE=$?
}

run_env_command "DDNS update" "${KEEPALIVED_MASTER_DDNS_CMD:-}"
run_env_command "SSL sync" "${KEEPALIVED_MASTER_SSL_SYNC_CMD:-}"

if [[ "$RAN_TASK" -eq 0 ]]; then
  [[ "$QUIET" -eq 1 ]] || echo "MASTER"
fi

exit "$EXIT_CODE"