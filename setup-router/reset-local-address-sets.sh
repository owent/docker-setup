#!/bin/bash

if [[ -e "/opt/nftables/sbin" ]]; then
  export PATH=/opt/nftables/sbin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/bin/site_perl:/usr/bin/vendor_perl:/usr/bin/core_perl
else
  export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/bin/site_perl:/usr/bin/vendor_perl:/usr/bin/core_perl
fi

cd "$(dirname "$(readlink -f "$0")")"

# ln -sf "$PWD/reset-local-address-sets.sh" /etc/NetworkManager/dispatcher.d/connectivity-change.d/91-reset-local-address-sets.sh
# Ensure /etc/NetworkManager/dispatcher.d/connectivity-change run /etc/NetworkManager/dispatcher.d/connectivity-change.d/*

nohup bash -c \
  "export ROUTER_NET_LOCAL_NFTABLE_NAME=v2ray:ip:ip6:bridge,nat:ip:ip6,security_firewall:inet ;
export ROUTER_NET_LOCAL_IPSET_PREFIX=V2RAY ;
flock --nonblock -E 0 /run/reset-local-address-sets.lock -c \"sleep 3 || usleep 3000000; /bin/bash $PWD/reset-local-address-set.sh\"
flock --nonblock -E 0 /run/reset-ipv6-dnp.lock -c \"sleep 3 || usleep 3000000; /bin/bash $PWD/ppp-nat/reset-ipv6-dnp.sh \"
" >"$PWD/reset-local-address-set.log" 2>&1 &
