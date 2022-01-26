#!/bin/bash

if [[ -e "/opt/nftables/sbin" ]]; then
  export PATH=/opt/nftables/sbin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/bin/site_perl:/usr/bin/vendor_perl:/usr/bin/core_perl
else
  export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/bin/site_perl:/usr/bin/vendor_perl:/usr/bin/core_perl
fi

cd "$(dirname "$(readlink -f "$0")")"

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

export ROUTER_NET_LOCAL_NFTABLE_NAME=v2ray:ip:ip6:bridge,nat:ip:ip6,security_firewall:inet
export ROUTER_NET_LOCAL_IPSET_PREFIX=V2RAY

bash "$PWD/reset-local-address-set.sh"
bash "$PWD/ppp-nat/reset-ipv6-ndp.sh"

echo "$CURRENT_VERSION" | tee /tmp/reset-local-address-sets.version
