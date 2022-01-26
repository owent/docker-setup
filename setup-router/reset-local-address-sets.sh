#!/bin/bash

if [[ -e "/opt/nftables/sbin" ]]; then
  export PATH=/opt/nftables/sbin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/bin/site_perl:/usr/bin/vendor_perl:/usr/bin/core_perl
else
  export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/bin/site_perl:/usr/bin/vendor_perl:/usr/bin/core_perl
fi

cd "$(dirname "$(readlink -f "$0")")"

# ln -sf "$PWD/reset-local-address-sets.sh" /etc/NetworkManager/dispatcher.d/connectivity-change.d/91-reset-local-address-sets.sh
# Ensure /etc/NetworkManager/dispatcher.d/connectivity-change run /etc/NetworkManager/dispatcher.d/connectivity-change.d/*

CURRENT_VERSION=$(date +%s)
nohup bash -c \
  "flock -w 300 -E 0 /run/reset-local-address-sets.lock -c \"sleep 3 || usleep 3000000; /bin/bash $PWD/reset-local-address-run.sh $CURRENT_VERSION | systemd-cat -t router-reset-local-address-sets -p info\"
" >"$PWD/reset-local-address-set.log" 2>&1 &
