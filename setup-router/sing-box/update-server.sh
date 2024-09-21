#!/bin/bash

cd "$(dirname "${BASH_SOURCE[0]}")"

export XDG_RUNTIME_DIR="/run/user/$UID"
export DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR}/bus"

systemctl --user status vbox-server.service

if [[ $? -ne 0 ]]; then
  bash setup-server.sh
else
  systemctl --user restart vbox-server.service
fi
