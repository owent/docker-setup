#!/bin/bash

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
source "$(dirname "$SCRIPT_DIR")/configure-router.sh"
cd "$SCRIPT_DIR"

# ln -sf "$PWD/delay-setup-multi-wan.sh" /etc/NetworkManager/dispatcher.d/connectivity-change.d/92-delay-setup-multi-wan.sh
# Ensure /etc/NetworkManager/dispatcher.d/connectivity-change run /etc/NetworkManager/dispatcher.d/connectivity-change.d/*

nohup bash -c \
  "flock --nonblock -E 0 /run/setup-multi-wan.lock -c \"/bin/bash $PWD/cleanup-multi-wan.sh; sleep 5 || usleep 5000000; /bin/bash $PWD/setup-multi-wan.sh\"" >"$PWD/setup-multi-wan.log" 2>&1 &
