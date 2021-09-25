#!/bin/bash

# connectivity-change or up
if [[ "x$NM_DISPATCHER_ACTION" != "xup" ]]; then
  exit 0;
fi

export PATH=$PATH:/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin:$HOME/bin:$HOME/.local/bin
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)";

source "$SCRIPT_DIR/setup-multi-wan-conf.sh" ;

mwan_in_watch_list "$DEVICE_IP_IFACE" || exit 0 ;

# Using journalctl -t router-mwan to see this log
echo "[$(date "+%F %T")]: $0 $@" | systemd-cat -t router-mwan -p info ;

mkdir -p /run/multi-wan/ ;

if [[ "x$IP4_GATEWAY" != "x" ]] && [[ "x$IP4_GATEWAY" != "x0.0.0.0" ]] && [[ "x$IP4_GATEWAY" != "x127.0.0.1" ]] ; then
  sed -i "/^$DEVICE_IP_IFACE\\b/d" /run/multi-wan/ipv4 ;
  echo "$DEVICE_IP_IFACE DEVICE_IFACE=\"$DEVICE_IFACE\" IP4_GATEWAY=\"$IP4_GATEWAY\"" >> /run/multi-wan/ipv4 ;
  for RECHECK_IFACE in $(cat /run/multi-wan/ipv4 | awk '{print $1}'); do
    ip -4 -o addr show dev $RECHECK_IFACE ;
    if [[ $? -ne 0 ]] && [[ "$RECHECK_IFACE" != "$DEVICE_IP_IFACE" ]]; then
      sed -i "/^$RECHECK_IFACE\\b/d" /run/multi-wan/ipv4 ;
    fi
  done
  chmod 777 /run/multi-wan/ipv4 ;
fi

if [[ "x$IP6_GATEWAY" != "x" ]] && [[ "x$IP6_GATEWAY" != "x0.0.0.0" ]] && [[ "x$IP6_GATEWAY" != "x127.0.0.1" ]] && [[ "x${IP6_GATEWAY:0:2}" != "x::" ]] ; then
  sed -i "/^$DEVICE_IP_IFACE\\b/d" /run/multi-wan/ipv6 ;
  echo "$DEVICE_IP_IFACE DEVICE_IFACE=\"$DEVICE_IFACE\" IP6_GATEWAY=\"$IP6_GATEWAY\"" >> /run/multi-wan/ipv6 ;
  for RECHECK_IFACE in $(cat /run/multi-wan/ipv6 | awk '{print $1}'); do
    ip -6 -o addr show dev $RECHECK_IFACE ;
    if [[ $? -ne 0 ]] && [[ "$RECHECK_IFACE" != "$DEVICE_IP_IFACE" ]]; then
      sed -i "/^$RECHECK_IFACE\\b/d" /run/multi-wan/ipv6 ;
    fi
  done
  chmod 777 /run/multi-wan/ipv6 ;
fi

bash "$SCRIPT_DIR/setup-multi-wan.sh" ;
