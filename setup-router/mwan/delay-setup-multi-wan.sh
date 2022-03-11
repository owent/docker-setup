#!/bin/bash

if [[ -e "/opt/nftables/sbin" ]]; then
  export PATH=/opt/nftables/sbin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/bin/site_perl:/usr/bin/vendor_perl:/usr/bin/core_perl
else
  export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/bin/site_perl:/usr/bin/vendor_perl:/usr/bin/core_perl
fi

cd "$(dirname "$(readlink -f "$0")")"

# ln -sf "$PWD/delay-setup-multi-wan.sh" /etc/NetworkManager/dispatcher.d/connectivity-change.d/92-delay-setup-multi-wan.sh
# Ensure /etc/NetworkManager/dispatcher.d/connectivity-change run /etc/NetworkManager/dispatcher.d/connectivity-change.d/*

nohup bash -c \
  "flock --nonblock -E 0 /run/setup-multi-wan.lock -c \"/bin/bash $PWD/cleanup-multi-wan.sh; sleep 5 || usleep 5000000; /bin/bash $PWD/setup-multi-wan.sh\"" >"$PWD/setup-multi-wan.log" 2>&1 &
