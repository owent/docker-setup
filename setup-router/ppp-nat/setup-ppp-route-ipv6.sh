#!/bin/bash

# /home/router/ppp-nat/setup-ppp-route-ipv6.sh
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

while [ ! -z "$(ip -6 route show default 2>/dev/null)" ]; do
    ip -6 route delete default ;
done

ip -6 route add ::/0 via $5 dev $1 ;

nft list set ip6 nat ppp-address > /dev/null 2>&1 ;
if [ $? -ne 0 ]; then
    nft add set ip6 nat ppp-address { type ipv6_addr\; }
fi
nft flush set ip6 nat ppp-address ;
nft add element ip6 nat ppp-address { $4, $5 } ;


# sync to v2ray BLACKLIST
nft list table ip6 v2ray > /dev/null 2>&1 ;
if [ $? -ne 0 ]; then
    nft add table ip6 v2ray
fi
nft list set ip6 v2ray BLACKLIST > /dev/null 2>&1 ;
if [ $? -ne 0 ]; then
    nft add set ip6 v2ray BLACKLIST { type ipv6_addr\; }
fi
nft flush set ip6 v2ray BLACKLIST ;
nft add element ip6 v2ray BLACKLIST { $4 } ;
