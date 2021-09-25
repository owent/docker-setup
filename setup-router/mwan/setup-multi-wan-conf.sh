#!/bin/bash

# These interfaces can not be used as inner bridge or local network
MWAN_WATCH_INERFACES=(enp1s0f2 ppp0 ppp1);
MWAN_INERFACES_WEIGHT=(5 1 1);

function mwan_in_watch_list() {
  for CHECK_INERFACE in ${MWAN_WATCH_INERFACES[@]}; do
    if [[ "$1" == "$CHECK_INERFACE" ]]; then
      return 0;
    fi
  done
  return 1;
}

function mwan_not_in_watch_list() {
  for CHECK_INERFACE in ${MWAN_WATCH_INERFACES[@]}; do
    if [[ "$1" == "$CHECK_INERFACE" ]]; then
      return 1;
    fi
  done
  return 0;
}


# if [[ "x$DEVICE_IFACE" == "x" ]]; then
#   export DEVICE_IFACE="$DEVICE";
# fi
# 
# if [[ "x$DEVICE_IP_IFACE" == "x" ]]; then
#   export DEVICE_IP_IFACE="$IFNAME";
# fi
# 
# if [[ "x$IP4_GATEWAY" == "x" ]]; then
#   export IP4_GATEWAY="$IPREMOTE";
# fi

