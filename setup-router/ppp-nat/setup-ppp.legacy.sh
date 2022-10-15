#!/bin/bash

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
source "$(dirname "$SCRIPT_DIR")/configure-router.sh"

if [[ -e "/lib/systemd/system" ]]; then
  export SETUP_SYSTEMD_SYSTEM_DIR=/lib/systemd/system
elif [[ -e "/usr/lib/systemd/system" ]]; then
  export SETUP_SYSTEMD_SYSTEM_DIR=/usr/lib/systemd/system
elif [[ -e "/etc/systemd/system" ]]; then
  export SETUP_SYSTEMD_SYSTEM_DIR=/etc/systemd/system
fi

if [[ "x$ROUTER_CONFIG_PPP_LINK_INTERFACE" != "x" ]]; then
  mkdir -p /opt/ppp/etc

  echo "
ppp_async
ppp_deflate
ppp_generic
ppp_mppe
pppoe
pppox
ppp_synctty
" | sudo tee /etc/modules-load.d/ppp.conf

  # It recommand to setup pppd with NetworkManager
  echo "
noauth
refuse-eap
user '$ROUTER_CONFIG_PPP_USERNAME'
password '$ROUTER_CONFIG_PPP_PASSWORD'
nomppe
plugin rp-pppoe.so
$ROUTER_CONFIG_PPP_LINK_INTERFACE
mru 1480 mtu 1480
persist
holdoff 10
maxfail 0
usepeerdns
ipcp-accept-remote ipcp-accept-local noipdefault
ktune
default-asyncmap nopcomp noaccomp
novj nobsdcomp nodeflate
lcp-echo-interval 30
lcp-echo-failure 3
unit 0
linkname $ROUTER_CONFIG_PPP_LINK_INTERFACE
+ipv6
" >/opt/ppp/etc/$ROUTER_CONFIG_PPP_LINK_INTERFACE

  echo "
[Unit]
Description=ppp-$ROUTER_CONFIG_PPP_LINK_INTERFACE Service
After=network.target network-online.target
Wants=network-online.target

[Service]
# User=ppp
# Group=ppp
Type=forking
PIDFile=/var/run/ppp-$ROUTER_CONFIG_PPP_LINK_INTERFACE.pid
ExecStart=/usr/sbin/pppd file /opt/ppp/etc/$ROUTER_CONFIG_PPP_LINK_INTERFACE
ExecStartPre=/bin/bash $ROUTER_HOME/ppp-nat/setup-ppp-up-down-rule.sh
Restart=on-failure
# Don't restart in the case of configuration error
RestartPreventExitStatus=23

[Install]
WantedBy=default.target
" >$SETUP_SYSTEMD_SYSTEM_DIR/pppd-$ROUTER_CONFIG_PPP_LINK_INTERFACE.service

fi
