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
while [ 0 -ne $FWMARK_LOOPUP_TABLE_100 ] ; do
    ip -4 rule delete fwmark 1 lookup 100
    FWMARK_LOOPUP_TABLE_100=$(ip -4 rule show fwmark 1 lookup 100 | awk 'END {print NF}')
done

FWMARK_LOOPUP_TABLE_100=$(ip -6 rule show fwmark 1 lookup 100 | awk 'END {print NF}')
while [ 0 -ne $FWMARK_LOOPUP_TABLE_100 ] ; do
    ip -6 rule delete fwmark 1 lookup 100
    FWMARK_LOOPUP_TABLE_100=$(ip -6 rule show fwmark 1 lookup 100 | awk 'END {print NF}')
done

# Cleanup ipv4
nft list table ip v2ray > /dev/null 2>&1 ;
if [ $? -eq 0 ]; then
    nft delete table ip v2ray ;
fi

# Cleanup ipv6
nft list table ip6 v2ray > /dev/null 2>&1 ;
if [ $? -eq 0 ]; then
    nft delete table ip6 v2ray ;
fi
