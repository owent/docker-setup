#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# see https://github.com/Neilpang/acme.sh for detail
# see https://github.com/Neilpang/acme.sh/wiki/How-to-issue-a-cert

# curl https://get.acme.sh | sh

# export CF_Key="GOT TOKEN FROM https://dash.cloudflare.com/profile"
# export CF_Email="admin@owent.net"

# In order to use the new token, the token currently needs access read access to Zone.Zone, and write access to Zone.DNS, across all Zones.
#export CF_Token="GOT TOKEN FROM https://dash.cloudflare.com/profile" ;
export CF_Account_ID="6896d432a993ce19d72862cc8450db09"

# Get CF_Account_ID using
#   curl -X GET "https://api.cloudflare.com/client/v4/zones" \
#     -H "Content-Type:application/json"                     \
#     -H "Authorization: Bearer $CF_Token"
# Or add read access to Account.Account Settings and then using
#    curl -X GET "https://api.cloudflare.com/client/v4/accounts" \
#      -H "Content-Type: application/json"                       \
#      -H "Authorization: Bearer $CF_Token"

DOMAIN_NAME=owent.net
ADMIN_EMAIL=$CF_Email
INSTALL_CERT_DIR=/home/tools/bitwarden/ssl

if [[ "x$ROUTER_HOME" == "x" ]] && [[ -e "$SCRIPT_DIR/../configure-router.sh" ]]; then
  source "$SCRIPT_DIR/../configure-router.sh"
fi

if [[ "x$ACMESH_SSL_DIR" == "x" ]]; then
  if [[ "x$ROUTER_HOME" != "x" ]]; then
    ACMESH_SSL_DIR=$ROUTER_HOME/acme.sh/ssl
  else
    ACMESH_SSL_DIR="$HOME/acme.sh/ssl"
  fi
fi
mkdir -p "$ACMESH_SSL_DIR"

# systemctl restart router-nginx
# systemctl restart v2ray
