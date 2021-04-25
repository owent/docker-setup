#!/bin/bash

export PATH=$PATH:/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin:$HOME/bin:$HOME/.local/bin
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)";

# Using journalctl -t docker-setup-ppp to see this log
echo "[$(date "+%F %T")]: $0 $@" | systemd-cat -t docker-setup-ppp -p info ;

mkdir -p /run/multi-wan/ ;
sed -i "/^$IFNAME\\b/d" /run/multi-wan/ipv4 ;
echo "$IFNAME DEVICE=\"$DEVICE\" IPLOCAL=\"$IPLOCAL\" IPREMOTE=\"$IPREMOTE\" PEERNAME=\"$PEERNAME\" SPEED=\"$SPEED\" LINKNAME=\"$LINKNAME\"" >> /run/multi-wan/ipv4 ;
for RECHECK_PPP_IF in $(cat /run/multi-wan/ipv4 | awk '{print $1}'); do
  ip -4 -o addr show dev $CHECK_PPP_IF ;
  if [[ $? -ne 0 ]]; then
    sed -i "/^$RECHECK_PPP_IF\\b/d" /run/multi-wan/ipv4 ;
  fi
done

bash "$SCRIPT_DIR/setup-multi-wan.sh" ;
