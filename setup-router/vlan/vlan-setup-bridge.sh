#!/bin/bash

# $ROUTER_HOME/vlan/vlan-setup-bridge.sh
# @see https://www.man7.org/linux/man-pages/man8/bridge.8.html
# @see https://man.archlinux.org/man/NetworkManager-dispatcher.8.en
#
# This script could be linked into /etc/NetworkManager/dispatcher.d/up.d/vlan-setup-bridge.sh
# parameters
#       $1      the interface name used by pppd (e.g. ppp3)
#       $2      the tty device name
#       $3      the tty device speed
#       $4      the local IP address for the interface
#       $5      the remote IP address
#       $6      the parameter specified by the 'ipparam' option to pppd
#

[ -e "/opt/podman" ] && export PATH="/opt/podman/bin:/opt/podman/libexec:$PATH"
export PATH="$PATH:/usr/local/sbin:/usr/local/bin:/usr/sbin:/sbin"

echo "[$(date "+%F %T")]: $0 $@
  CONNECTION_ID=$CONNECTION_ID
  CONNECTION_UUID=$CONNECTION_UUID
  NM_DISPATCHER_ACTION=$NM_DISPATCHER_ACTION
  CONNECTIVITY_STATE=$CONNECTIVITY_STATE
  DEVICE_IFACE=$DEVICE_IFACE
  DEVICE_IP_IFACE=$DEVICE_IP_IFACE
  IP4_GATEWAY=$IP4_GATEWAY
  IP6_GATEWAY=$IP6_GATEWAY
" | systemd-cat -t router-vlan -p info

if [[ -z "$NM_DISPATCHER_ACTION" ]] || [[ -z "$DEVICE_IFACE" ]]; then
  exit 0
fi

if [[ "$NM_DISPATCHER_ACTION" != "up" ]]; then
  exit 0
fi

BRIDGE_SETUP_VLAN_ID=
BRIDGE_SETUP_VLAN_IFNAME=
BRIDGE_SETUP_VLAN_MASTER_IFNAME=
BRIDGE_SETUP_VLAN_SLAVE_IFNAMES=()

if [[ "$DEVICE_IFACE" == "enp8s0" ]] || [[ "$DEVICE_IFACE" == "enp7s0" ]]; then
  ACTIVED_VLAN=($(nmcli --fields NAME,TYPE,DEVICE connection show --active | awk '$2 == "vlan" { print $3 }'))
  for VLAN_NAME in ${ACTIVED_VLAN[@]}; do
    if [[ "$VLAN_NAME" == "vlan0" ]]; then
      BRIDGE_SETUP_VLAN_ID=3
      BRIDGE_SETUP_VLAN_IFNAME=br0
      BRIDGE_SETUP_VLAN_IFNAME=vlan0
      BRIDGE_SETUP_VLAN_SLAVE_IFNAMES=($DEVICE_IFACE)
      break
    fi
  done
elif [[ "$DEVICE_IFACE" == "vlan0" ]]; then
  ACTIVED_ETH=($(nmcli --fields NAME,TYPE,DEVICE connection show --active | awk '$2 == "ethernet" { print $3 }'))
  BRIDGE_SETUP_VLAN_ID=3
  BRIDGE_SETUP_VLAN_IFNAME=br0
  BRIDGE_SETUP_VLAN_IFNAME=vlan0
  for ETH_NAME in ${ACTIVED_ETH[@]}; do
    if [[ "$ETH_NAME" == "enp8s0" ]] || [[ "$ETH_NAME" == "enp7s0" ]]; then
      BRIDGE_SETUP_VLAN_SLAVE_IFNAMES=(${BRIDGE_SETUP_VLAN_SLAVE_IFNAMES[@]} $ETH_NAME)
    fi
  done
fi

if [[ ${#BRIDGE_SETUP_VLAN_SLAVE_IFNAMES[@]} -eq 0 ]]; then
  exit 0
fi

for SLAVE_IFNAME in ${BRIDGE_SETUP_VLAN_SLAVE_IFNAMES[@]}; do
  bridge vlan del vid 1 dev $SLAVE_IFNAME
  bridge vlan add vid $BRIDGE_SETUP_VLAN_ID pvid untagged dev $SLAVE_IFNAME
done

echo "[$(date "+%F %T")]: $(bridge vlan show)" | systemd-cat -t router-vlan -p info
