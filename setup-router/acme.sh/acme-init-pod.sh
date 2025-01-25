#!/bin/bash

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
source "$(dirname "$SCRIPT_DIR")/configure-router.sh"

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

if [[ "x$ACMESH_SSL_DIR" == "x" ]]; then
  if [[ "x$ROUTER_HOME" != "x" ]]; then
    ACMESH_SSL_DIR=$ROUTER_HOME/acme.sh/ssl
  else
    ACMESH_SSL_DIR="$HOME/acme.sh/ssl"
  fi
fi
mkdir -p "$ACMESH_SSL_DIR"

# podman exec acme.sh acme.sh --register-account -m $CF_Email

if [[ "x$ACMESH_ACTION" == "renewx" ]]; then
  ACMESH_ACTION_OPTIONS=(--renew-all)
elif [[ "x$ACMESH_ACTION" == "registerx" ]]; then
  ACMESH_ACTION_OPTIONS=(--register-account -m $CF_Email)
else
  ACMESH_ACTION_OPTIONS=(--renew-all)
  ACMESH_ACTION_OPTIONS=(--force --issue
    -d "$DOMAIN_NAME" -d "*.$DOMAIN_NAME"
    -d "r-ci.com" -d "*.r-ci.com"
    --dns dns_cf
    --keylength ec-384)
  # 2048, 3072, 4096, 8192 or ec-256, ec-384, ec-521
fi

podman exec \
  -e CF_Email=$CF_Email \
  -e CF_Account_ID=$CF_Account_ID \
  -e CF_Token=$CF_Token \
  acme.sh acme.sh "${ACMESH_ACTION_OPTIONS[@]}" "$@"

# sudo -u tools crontab -e
# 32 4 * * * /bin/bash /data/setup/acme.sh/acme-renew.sh > /dev/null
