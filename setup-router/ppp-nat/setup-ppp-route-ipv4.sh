#!/bin/bash

# /home/router/ppp-nat/setup-ppp-route-ipv4.sh
# @see https://linux.die.net/man/8/pppd
#
# When the ppp link comes up, this script is called with the following
# parameters
#       $1      the interface name used by pppd (e.g. ppp3)
#       $2      the tty device name
#       $3      the tty device speed
#       $4      the local IP address for the interface
#       $5      the remote IP address
#       $6      the parameter specified by the 'ipparam' option to pppd
#

if [[ -e "/opt/nftables/sbin" ]]; then
    export PATH=/opt/nftables/sbin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/bin/site_perl:/usr/bin/vendor_perl:/usr/bin/core_perl
else
    export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/bin/site_perl:/usr/bin/vendor_perl:/usr/bin/core_perl
fi

# Using journalctl -t router-ppp to see this log
echo "[$(date "+%F %T")]: $0 $@" | systemd-cat -t router-ppp -p info ;

cd "$(dirname "${BASH_SOURCE[0]}")" ;

# while [ ! -z "$(ip route show default 2>/dev/null)" ]; do
#     ip -4 route delete default ;
# done
# ip -4 route add default via XXX dev $1 ;
# ip -4 route add 0.0.0.0/0 via $IPREMOTE dev $IFNAME ;

if [[ -e "/etc/resolv.conf.dnsmasq" ]]; then
    cp -f /etc/resolv.conf.dnsmasq /etc/resolv.conf;
fi
