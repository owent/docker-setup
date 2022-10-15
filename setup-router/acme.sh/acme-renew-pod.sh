#!/bin/bash

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
source "$(dirname "$SCRIPT_DIR")/configure-router.sh"

if [[ "x$ACMESH_SSL_DIR" == "x" ]]; then
  if [[ "x$ROUTER_HOME" != "x" ]]; then
    ACMESH_SSL_DIR=$ROUTER_HOME/acme.sh/ssl
  else
    ACMESH_SSL_DIR="$HOME/acme.sh/ssl"
  fi
fi
mkdir -p "$ACMESH_SSL_DIR"

# sudo -u tools bash -c 'source ~/.bashrc; systemctl restart --user router-nginx'
# systemctl restart v2ray
