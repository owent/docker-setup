#!/bin/bash

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"

if [[ -e "$(dirname "$SCRIPT_DIR")/configure-router.sh" ]]; then
  source "$(dirname "$SCRIPT_DIR")/configure-router.sh"
fi

if [[ -z "$ACMESH_SSL_DIR" ]]; then
  if [[ -n "$ROUTER_DATA_ROOT_DIR" ]]; then
    ACMESH_SSL_DIR=$ROUTER_DATA_ROOT_DIR/acme.sh/ssl
  else
    ACMESH_SSL_DIR="$HOME/acme.sh/ssl"
  fi
fi
mkdir -p "$ACMESH_SSL_DIR"

# sudo -u tools bash -c 'source ~/.bashrc; systemctl restart --user router-nginx'
# systemctl restart vbox-server

export XDG_RUNTIME_DIR="/run/user/$UID"
export DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR}/bus"

systemctl --user --all | grep -F adguardhome
if [[ $? -eq 0 ]]; then
  systemctl --user restart adguardhome
fi

systemctl --user --all | grep -F router-caddy
if [[ $? -eq 0 ]]; then
  systemctl --user restart router-caddy
fi

# Deploy to other service nodes
if [[ -e "$SCRIPT_DIR/acme-remote-deploy.sh" ]]; then
  /bin/bash "$SCRIPT_DIR/acme-remote-deploy.sh"
fi
