#!/bin/bash

# /home/router/ppp-nat/cleanup-ppp-route-ipv4.sh
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

ip -4 route delete 0.0.0.0/0 via $IPREMOTE dev $IFNAME ;

which nft > /dev/null 2>&1 ;
if [[ $? -eq 0 ]]; then
    # sync to v2ray BLACKLIST/IPLOCAL
    nft list table ip v2ray > /dev/null 2>&1 ;
    if [[ $? -ne 0 ]]; then
        nft add table ip v2ray
    fi
    nft list set ip v2ray BLACKLIST > /dev/null 2>&1 ;
    if [[ $? -ne 0 ]]; then
        nft add set ip v2ray BLACKLIST { type ipv4_addr\; }
    fi
    nft delete element ip v2ray BLACKLIST { $IPLOCAL } ;

    nft list set ip nat IPLOCAL > /dev/null 2>&1 ;
    if [[ $? -ne 0 ]]; then
        nft add set ip nat IPLOCAL { type ipv4_addr\; }
    fi
    nft delete element ip nat IPLOCAL { $IPLOCAL } ;
fi

which ipset > /dev/null 2>&1 ;
if [[ $? -eq 0 ]]; then
    ipset list V2RAY_BLACKLIST_IPV4 > /dev/null 2>&1 ;
    if [[ $? -ne 0 ]]; then
        ipset create V2RAY_BLACKLIST_IPV4 hash:ip family inet;
    fi
    ipset del V2RAY_BLACKLIST_IPV4 $IPLOCAL;

    ipset list NAT_IPLOCAL_IPV4 > /dev/null 2>&1 ;
    if [[ $? -ne 0 ]]; then
        ipset create NAT_IPLOCAL_IPV4 hash:ip family inet;
    fi
    ipset del NAT_IPLOCAL_IPV4 $IPLOCAL;
fi

