#!/bin/bash

# down
if [[ "x$NM_DISPATCHER_ACTION" != "xdown" ]]; then
  exit 0;
fi

export PATH=$PATH:/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin:$HOME/bin:$HOME/.local/bin
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)";

source "$SCRIPT_DIR/setup-multi-wan-conf.sh" ;

mwan_in_watch_list "$DEVICE_IP_IFACE" || exit 0 ;

# Using journalctl -t router-mwan to see this log
echo "[$(date "+%F %T")]: $0 $@
  CONNECTION_ID=$CONNECTION_ID
  CONNECTION_UUID=$CONNECTION_UUID
  NM_DISPATCHER_ACTION=$NM_DISPATCHER_ACTION
  CONNECTIVITY_STATE=$CONNECTIVITY_STATE
  DEVICE_IFACE=$DEVICE_IFACE
  DEVICE_IP_IFACE=$DEVICE_IP_IFACE" | systemd-cat -t router-mwan -p info ;

if [[ "x$IP4_GATEWAY" != "x" ]]; then
  if [[ -e "/run/multi-wan/ipv4" ]]; then
    sed -i "/^$DEVICE_IP_IFACE\\b/d" /run/multi-wan/ipv4 ;
  fi
fi

if [[ "x$IP6_GATEWAY" != "x" ]]; then
  if [[ -e "/run/multi-wan/ipv6" ]]; then
    sed -i "/^$DEVICE_IP_IFACE\\b/d" /run/multi-wan/ipv6 ;
  fi
fi

bash "$SCRIPT_DIR/setup-multi-wan.sh" ;
