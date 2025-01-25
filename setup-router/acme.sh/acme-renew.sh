#!/bin/bash

# see https://github.com/Neilpang/acme.sh for detail
# see https://github.com/Neilpang/acme.sh/wiki/How-to-issue-a-cert

# curl https://get.acme.sh | sh

DOMAIN_NAME=owent.net
ACMESH_SSL_DIR=/home/tools/bitwarden/ssl
REMOTE_DEPLOY_KEY=<path of id_ed25519>

# using a custom port
# ACME_SH_HTTP_PROT=88;
# firewall-cmd --add-port=tcp/$ACME_SH_TLS_PROT/tcp;
# firewall-cmd --reload;

# using a custom tls port
# ACME_SH_TLS_PROT=8443;
# firewall-cmd --add-port=tcp/$ACME_SH_TLS_PROT/tcp;
# firewall-cmd --reload;

if [[ "root" == "$(id -un)" ]]; then
  echo "$0 should not be run with root"
  exit 1
fi

"$HOME/.acme.sh"/acme.sh --cron --home "$HOME/.acme.sh"

cp -f ~/.acme.sh/${DOMAIN_NAME}*/* $ACMESH_SSL_DIR;


# Restart local services
export XDG_RUNTIME_DIR="/run/user/$UID"
export DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR}/bus"
systemctl --user restart container-bitwarden;
systemctl --user restart nginx.service;

# Copy to remote
# bash $PWD/acme-remote-deploy.sh
