#!/bin/bash

cd "$(dirname "${BASH_SOURCE[0]}")";

if [ -e "/opt/nftables/sbin" ]; then
    export PATH=/opt/nftables/sbin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/bin/site_perl:/usr/bin/vendor_perl:/usr/bin/core_perl
else
    export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/bin/site_perl:/usr/bin/vendor_perl:/usr/bin/core_perl
fi

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

# export ROUTER_CONFIG_PPP_LINK_INTERFACE=<PPP wan interface> # enp1s0f3, wan0 ?
# export ROUTER_CONFIG_PPP_USERNAME=<PPPOE USER NAME>
# export ROUTER_CONFIG_PPP_PASSWORD=<PPPOE USER PASSWORD>

if [ "x$ROUTER_CONFIG_PPP_LINK_INTERFACE" != "x" ]; then
    /bin/bash setup-ppp.sh ;
    systemctl daemon-reload ;
    systemctl enable pppd-$ROUTER_CONFIG_PPP_LINK_INTERFACE ;
    systemctl start pppd-$ROUTER_CONFIG_PPP_LINK_INTERFACE ;
else
    # Setup pppd with NetworkMansger on host
    /bin/bash /home/router/ppp-nat/setup-ppp-up-down-rule.sh
fi

# Notice: gateways's ip must match the configure in setup-dnsmasq.sh and setup-nat-ssh.sh
#             fd27:32d6:ac12:XXXX/64 for ipv6
#             172.18.X.X/16 for ipv4
if [ "x$ROUTER_CONFIG_IPV6_INTERFACE" == "x" ]; then
    if [ "x$ROUTER_CONFIG_PPP_LINK_INTERFACE" != "x" ]; then
        export ROUTER_CONFIG_IPV6_INTERFACE=$ROUTER_CONFIG_PPP_LINK_INTERFACE
    fi
fi

/bin/bash setup-dnsmasq.sh ;

systemctl daemon-reload ;
systemctl enable dnsmasq ;

if [ "x$ROUTER_CONFIG_ON_FINISH_RUN" == "x" ]; then
    chmod +x "$ROUTER_CONFIG_ON_FINISH_RUN";
    "$ROUTER_CONFIG_ON_FINISH_RUN";
fi
