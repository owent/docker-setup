#!/bin/bash

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"

export XDG_RUNTIME_DIR="/run/user/$UID"
export DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR}/bus"

if [[ -z "$ACMESH_SSL_DIR" ]]; then
  if [[ -n "$ROUTER_DATA_ROOT_DIR" ]]; then
    ACMESH_SSL_DIR=$ROUTER_DATA_ROOT_DIR/acme.sh/ssl
  else
    ACMESH_SSL_DIR="$SCRIPT_DIR/ssl"
  fi
fi

# systemctl --user restart router-caddy

