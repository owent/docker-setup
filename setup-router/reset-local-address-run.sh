#!/bin/bash

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
source "$SCRIPT_DIR/configure-router.sh"

cd "$SCRIPT_DIR"

set -x
COMPARE_VERSION=$1
CURRENT_VERSION=$(date +%s)
OLD_VERSION=0
if [[ -e "/tmp/reset-local-address-sets.version" ]]; then
  OLD_VERSION=$(cat /tmp/reset-local-address-sets.version)
fi

if [[ $OLD_VERSION -gt $COMPARE_VERSION ]]; then
  echo "Old version is greater than current version"
  exit 0
fi

ROUTER_NET_LOCAL_NFTABLE_NAME=""
ROUTER_NET_LOCAL_IPSET_PREFIX=""
if [ $ROUTER_NET_LOCAL_ENABLE_V2RAY -ne 0 ]; then
  if [ $TPROXY_SETUP_NFTABLES -ne 0 ]; then
    ROUTER_NET_LOCAL_NFTABLE_NAME=v2ray:ip:ip6:bridge
  else
    ROUTER_NET_LOCAL_IPSET_PREFIX=V2RAY
  fi
fi
if [ $ROUTER_NET_LOCAL_ENABLE_NAT -ne 0 ]; then
  if [[ -z "$ROUTER_NET_LOCAL_NFTABLE_NAME" ]]; then
    ROUTER_NET_LOCAL_NFTABLE_NAME="nat:ip:ip6"
  else
    ROUTER_NET_LOCAL_NFTABLE_NAME="$ROUTER_NET_LOCAL_NFTABLE_NAME,nat:ip:ip6"
  fi
fi
if [ $ROUTER_NET_LOCAL_ENABLE_SECURITY -ne 0 ]; then
  if [[ -z "$ROUTER_NET_LOCAL_NFTABLE_NAME" ]]; then
    ROUTER_NET_LOCAL_NFTABLE_NAME="security_firewall:inet"
  else
    ROUTER_NET_LOCAL_NFTABLE_NAME="$ROUTER_NET_LOCAL_NFTABLE_NAME,security_firewall:inet"
  fi
fi
export ROUTER_NET_LOCAL_NFTABLE_NAME
export ROUTER_NET_LOCAL_IPSET_PREFIX

bash "$PWD/reset-local-address-set.sh"
bash "$PWD/ppp-nat/reset-ipv6-ndp.sh"

echo "$CURRENT_VERSION" | tee /tmp/reset-local-address-sets.version
