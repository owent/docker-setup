#!/bin/bash

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
source "$SCRIPT_DIR/configure-router.sh"

cd "$SCRIPT_DIR"

# ln -sf "$PWD/reset-local-address-sets.sh" /etc/NetworkManager/dispatcher.d/connectivity-change.d/91-reset-local-address-sets.sh
# Ensure /etc/NetworkManager/dispatcher.d/connectivity-change run /etc/NetworkManager/dispatcher.d/connectivity-change.d/*

CURRENT_VERSION=$(date +%s)
nohup bash -c \
  "flock -w 300 -E 0 /run/reset-local-address-sets.lock -c \"sleep 3 || usleep 3000000; /bin/bash $PWD/reset-local-address-run.sh $CURRENT_VERSION 2>&1 | systemd-cat -t router-reset-local-address-sets -p info\"
" >"$PWD/reset-local-address-set.log" 2>&1 &
