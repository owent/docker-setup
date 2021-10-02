#!/bin/bash

if [[ -e "/opt/nftables/sbin" ]]; then
  export PATH=/opt/nftables/sbin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/bin/site_perl:/usr/bin/vendor_perl:/usr/bin/core_perl
else
  export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/bin/site_perl:/usr/bin/vendor_perl:/usr/bin/core_perl
fi

cd "$(dirname "$0")"

# ln -sf "$PWD/reset-local-address-sets.sh" /etc/NetworkManager/dispatcher.d/up.d/99-reset-local-address-sets.sh
# Ensure /etc/NetworkManager/dispatcher.d/up run /etc/NetworkManager/dispatcher.d/up.d/*
# ln -sf "$PWD/reset-local-address-sets.sh" /etc/NetworkManager/dispatcher.d/down.d/99-reset-local-address-sets.sh
# Ensure /etc/NetworkManager/dispatcher.d/down run /etc/NetworkManager/dispatcher.d/down.d/*

env ROUTER_NET_LOCAL_NFTABLE_NAME=v2ray,nat,mwan ROUTER_NET_LOCAL_IPSET_PREFIX=V2RAY bash "$PWD/reset-local-address-set.sh"
