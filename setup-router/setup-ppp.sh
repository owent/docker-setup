#!/bin/bash

if [ -e "/opt/nftables/sbin" ]; then
    export PATH=/opt/nftables/sbin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/bin/site_perl:/usr/bin/vendor_perl:/usr/bin/core_perl
else
    export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/bin/site_perl:/usr/bin/vendor_perl:/usr/bin/core_perl
fi

if [ "x$ROUTER_CONFIG_PPP_LINK_INTERFACE" != "x" ]; then
mkdir -p /opt/ppp/etc ;

echo "
ppp_async
ppp_deflate
ppp_generic
ppp_mppe
pppoe
pppox
ppp_synctty
" | sudo tee /etc/modules-load.d/ppp.conf

echo "
noauth
refuse-eap
user '$ROUTER_CONFIG_PPP_USERNAME'
password '$ROUTER_CONFIG_PPP_PASSWORD'
nomppe
plugin rp-pppoe.so
$ROUTER_CONFIG_PPP_LINK_INTERFACE
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
Type=forking
PIDFile=/var/run/ppp-$ROUTER_CONFIG_PPP_LINK_INTERFACE.pid
ExecStart=/usr/sbin/pppd file /opt/ppp/etc/$ROUTER_CONFIG_PPP_LINK_INTERFACE
ExecStartPre=/bin/bash /home/router/ppp-nat/setup-ppp-up-down-rule.sh
Restart=on-failure
# Don't restart in the case of configuration error
RestartPreventExitStatus=23

[Install]
WantedBy=multi-user.target
" > $SETUP_SYSTEMD_SYSTEM_DIR/pppd-$ROUTER_CONFIG_PPP_LINK_INTERFACE.service ;

fi