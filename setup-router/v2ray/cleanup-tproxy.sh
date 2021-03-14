#!/bin/bash

if [ -e "/opt/nftables/sbin" ]; then
    export PATH=/opt/nftables/sbin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/bin/site_perl:/usr/bin/vendor_perl:/usr/bin/core_perl
else
    export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/bin/site_perl:/usr/bin/vendor_perl:/usr/bin/core_perl
fi

## Cleanup hooks
ip -4 route delete local 0.0.0.0/0 dev lo table 100
ip -6 route delete local ::/0 dev lo table 100

FWMARK_LOOPUP_TABLE_100=$(ip -4 rule show fwmark 1 lookup 100 | awk 'END {print NF}')
while [[ 0 -ne $FWMARK_LOOPUP_TABLE_100 ]] ; do
    ip -4 rule delete fwmark 1 lookup 100
    FWMARK_LOOPUP_TABLE_100=$(ip -4 rule show fwmark 1 lookup 100 | awk 'END {print NF}')
done

FWMARK_LOOPUP_TABLE_100=$(ip -6 rule show fwmark 1 lookup 100 | awk 'END {print NF}')
while [[ 0 -ne $FWMARK_LOOPUP_TABLE_100 ]] ; do
    ip -6 rule delete fwmark 1 lookup 100
    FWMARK_LOOPUP_TABLE_100=$(ip -6 rule show fwmark 1 lookup 100 | awk 'END {print NF}')
done


# Cleanup ipv4
iptables -t mangle -D PREROUTING -j V2RAY > /dev/null 2>&1 ;
while [[ $? -eq 0 ]]; do
    iptables -t mangle -D PREROUTING -j V2RAY > /dev/null 2>&1;
done
iptables -t mangle -D OUTPUT -j V2RAY_MASK > /dev/null 2>&1 ;
while [[ $? -eq 0 ]]; do
    iptables -t mangle -D OUTPUT -j V2RAY_MASK > /dev/null 2>&1;
done
iptables -t mangle -X PREROUTING > /dev/null 2>&1;
iptables -t mangle -X OUTPUT > /dev/null 2>&1;


# Cleanup ipv6
ip6tables -t mangle -D PREROUTING -j V2RAY > /dev/null 2>&1 ;
while [[ $? -eq 0 ]]; do
    ip6tables -t mangle -D PREROUTING -j V2RAY > /dev/null 2>&1;
done
ip6tables -t mangle -D OUTPUT -j V2RAY_MASK > /dev/null 2>&1 ;
while [[ $? -eq 0 ]]; do
    ip6tables -t mangle -D OUTPUT -j V2RAY_MASK > /dev/null 2>&1;
done
ip6tables -t mangle -X PREROUTING > /dev/null 2>&1;
ip6tables -t mangle -X OUTPUT > /dev/null 2>&1;

# Cleanup bridge
ebtables -t broute -D BROUTING -j V2RAY_BRIDGE > /dev/null 2>&1 ;
while [[ $? -eq 0 ]]; do
    ebtables -t broute -D BROUTING -j V2RAY_BRIDGE > /dev/null 2>&1;
done
ebtables -t broute -X V2RAY_BRIDGE > /dev/null 2>&1;