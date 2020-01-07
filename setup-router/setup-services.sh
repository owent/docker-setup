#!/bin/bash

cd "$(dirname $0)" ;

if [ -e "/lib/systemd/system" ]; then
    export SETUP_SYSTEMD_SYSTEM_DIR=/lib/systemd/system;
elif [ -e "/usr/lib/systemd/system" ]; then
    export SETUP_SYSTEMD_SYSTEM_DIR=/usr/lib/systemd/system;
elif [ -e "/etc/systemd/system" ]; then
    export SETUP_SYSTEMD_SYSTEM_DIR=/etc/systemd/system;
if

if [ "x$ROUTER_CONFIG_ENV_FILE" != "x" ]; then
    source "$ROUTER_CONFIG_ENV_FILE";
fi

# Notice: gateways's ip must match the configure in setup-dnsmasq.sh and setup-nat-ssh.sh
#             fd27:32d6:ac12:XXXX/64 for ipv6
#             172.18.X.X/16 for ipv4
if [ "x$ROUTER_CONFIG_IPV6_INTERFACE" == "x" ]; then
    if [ "x$ROUTER_CONFIG_PPP_LINK_INTERFACE" != "x" ]; then
        export ROUTER_CONFIG_IPV6_INTERFACE=$ROUTER_CONFIG_PPP_LINK_INTERFACE
    fi
fi

# ROUTER_CONFIG_PPP_USERNAME
# ROUTER_CONFIG_PPP_PASSWORD
# ROUTER_CONFIG_PPP_LINK_INTERFACE=wan0

/bin/bash setup-ppp.sh ;
/bin/bash setup-dnsmasq.sh ;
/bin/bash setup-nat-ssh.sh ;

systemctl enable dnsmasq ;
if [ "x$ROUTER_CONFIG_PPP_LINK_INTERFACE" != "x" ]; then
    systemctl enable pppd-$ROUTER_CONFIG_PPP_LINK_INTERFACE ;
fi

if [ "x$ROUTER_CONFIG_ON_FINISH_RUN" == "x" ]; then
    chmod +x "$ROUTER_CONFIG_ON_FINISH_RUN";
    "$ROUTER_CONFIG_ON_FINISH_RUN";
fi

if [ -e "/lib/systemd/systemd" ]; then
    /lib/systemd/systemd
elif [ -e "/sbin/init" ]; then
    /sbin/init
fi