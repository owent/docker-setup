#!/bin/bash

if [ "x$ROUTER_CONFIG_PPP_LINK_INTERFACE" != "x" ]; then
mkdir -p /opt/ppp/etc ;

echo "
noauth
refuse-eap
user '$ROUTER_CONFIG_PPP_USERNAME'
password '$ROUTER_CONFIG_PPP_PASSWORD'
nomppe nomppc
plugin rp-pppoe.so nic-eth0
mru 1492 mtu 1492
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
lcp-echo-adaptive
unit 0
linkname $ROUTER_CONFIG_PPP_LINK_INTERFACE
+ipv6
" > /opt/ppp/etc/$ROUTER_CONFIG_PPP_LINK_INTERFACE ;

echo "
[Unit]
Description=ppp-$ROUTER_CONFIG_PPP_LINK_INTERFACE Service
After=network.target
Wants=network.target

[Service]
# User=ppp
# Group=ppp
Type=simple
PIDFile=/var/run/ppp-$ROUTER_CONFIG_PPP_LINK_INTERFACE.pid
ExecStart=/usr/sbin/pppd file /opt/ppp/etc/$ROUTER_CONFIG_PPP_LINK_INTERFACE
Restart=on-failure
# Don't restart in the case of configuration error
RestartPreventExitStatus=23

[Install]
WantedBy=multi-user.target
" > $SETUP_SYSTEMD_SYSTEM_DIR/pppd-$ROUTER_CONFIG_PPP_LINK_INTERFACE.service ;

fi