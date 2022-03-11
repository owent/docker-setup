#!/bin/bash

if [[ -e "/opt/nftables/sbin" ]]; then
  export PATH=/opt/nftables/sbin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/bin/site_perl:/usr/bin/vendor_perl:/usr/bin/core_perl
else
  export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/bin/site_perl:/usr/bin/vendor_perl:/usr/bin/core_perl
fi

## Cleanup hooks
ip -4 route delete local 0.0.0.0/0 dev lo table 100
ip -6 route delete local ::/0 dev lo table 100

FWMARK_LOOPUP_TABLE_IDS=($(ip -4 rule show fwmark 0x0e/0x0f lookup 100 | awk 'END {print $NF}'))
for TABLE_ID in ${FWMARK_LOOPUP_TABLE_IDS[@]}; do
  ip -4 rule delete fwmark 0x0e/0x0f lookup $TABLE_ID
  ip -4 route delete local 0.0.0.0/0 dev lo table $TABLE_ID
done

FWMARK_LOOPUP_TABLE_IDS=($(ip -6 rule show fwmark 0x0e/0x0f lookup 100 | awk 'END {print $NF}'))
for TABLE_ID in ${FWMARK_LOOPUP_TABLE_IDS[@]}; do
  ip -6 rule delete fwmark 0x0e/0x0f lookup $TABLE_ID
  ip -6 route delete local ::/0 dev lo table $TABLE_ID
done

# Cleanup ipv4
nft list chain ip v2ray PREROUTING >/dev/null 2>&1
if [[ $? -eq 0 ]]; then
  nft delete chain ip v2ray PREROUTING
fi
nft list chain ip v2ray OUTPUT >/dev/null 2>&1
if [[ $? -eq 0 ]]; then
  nft delete chain ip v2ray OUTPUT
fi

# Cleanup ipv6
nft list chain ip6 v2ray PREROUTING >/dev/null 2>&1
if [[ $? -eq 0 ]]; then
  nft delete chain ip6 v2ray PREROUTING
fi

nft list chain ip6 v2ray OUTPUT >/dev/null 2>&1
if [[ $? -eq 0 ]]; then
  nft delete chain ip6 v2ray OUTPUT
fi

# Cleanup bridge
nft list chain bridge v2ray PREROUTING >/dev/null 2>&1
if [[ $? -eq 0 ]]; then
  nft delete chain bridge v2ray PREROUTING
fi
