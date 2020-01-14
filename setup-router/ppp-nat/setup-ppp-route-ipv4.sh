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

if [ -e "/opt/nftables/sbin" ]; then
    export PATH=/opt/nftables/sbin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/bin/site_perl:/usr/bin/vendor_perl:/u    sr/bin/core_perl
else
    export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/bin/site_perl:/usr/bin/vendor_perl:/usr/bin/core_perl
fi

cd "$(dirname "${BASH_SOURCE[0]}")" ;

while [ ! -z "$(ip route show default 2>/dev/null)" ]; do
    ip -4 route delete default ;
done
# ip -4 route add default via XXX dev $1 ;
ip -4 route add 0.0.0.0/0 via $5 dev $1 ;

nft list set ip nat ppp-address > /dev/null 2>&1 ;
if [ $? -ne 0 ]; then
    nft add set ip nat ppp-address { type ipv4_addr\; }
fi
nft flush set ip nat ppp-address ;
nft add element ip nat ppp-address { $4, $5 } ;


# sync to v2ray-blacklist
nft list table ip mangle > /dev/null 2>&1 ;
if [ $? -ne 0 ]; then
    nft add table ip mangle
fi
nft list set ip mangle v2ray-blacklist > /dev/null 2>&1 ;
if [ $? -ne 0 ]; then
    nft add set ip mangle v2ray-blacklist { type ipv4_addr\; }
fi
nft flush set ip mangle v2ray-blacklist ;
nft add element ip mangle v2ray-blacklist { $4 } ;
