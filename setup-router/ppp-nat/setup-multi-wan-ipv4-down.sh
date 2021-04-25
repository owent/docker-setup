#!/bin/bash

export PATH=$PATH:/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin:$HOME/bin:$HOME/.local/bin
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)";

# Using journalctl -t docker-setup-ppp to see this log
echo "[$(date "+%F %T")]: $0 $@" | systemd-cat -t docker-setup-ppp -p info ;

if [[ -e "/run/multi-wan/ipv4" ]]; then
  sed -i "/^$IFNAME\\b/d" /run/multi-wan/ipv4 ;
fi

bash "$SCRIPT_DIR/setup-multi-wan.sh" ;
