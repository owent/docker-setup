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

if [ $TPROXY_SETUP_NFTABLES -ne 0 ]; then
  export ROUTER_NET_LOCAL_NFTABLE_NAME=v2ray:ip:ip6:bridge,nat:ip:ip6,security_firewall:inet
  export ROUTER_NET_LOCAL_IPSET_PREFIX=
else
  export ROUTER_NET_LOCAL_NFTABLE_NAME=nat:ip:ip6,security_firewall:inet
  export ROUTER_NET_LOCAL_IPSET_PREFIX=V2RAY
fi

bash "$PWD/reset-local-address-set.sh"
bash "$PWD/ppp-nat/reset-ipv6-ndp.sh"

echo "$CURRENT_VERSION" | tee /tmp/reset-local-address-sets.version
