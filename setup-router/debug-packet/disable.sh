#!/bin/bash

DEBUG_TPROXY_TABLE_ID=89

nft list table inet debug >/dev/null 2>&1
if [[ $? -eq 0 ]]; then
  nft delete table inet debug
fi

nft list table ip debug >/dev/null 2>&1
if [[ $? -eq 0 ]]; then
  nft delete table ip debug
fi

nft list table ip6 debug >/dev/null 2>&1
if [[ $? -eq 0 ]]; then
  nft delete table ip6 debug
fi

nft list table bridge debug >/dev/null 2>&1
if [[ $? -eq 0 ]]; then
  nft delete table bridge debug
fi

## Cleanup hooks
ip -4 route delete local 0.0.0.0/0 dev lo table $DEBUG_TPROXY_TABLE_ID
ip -6 route delete local ::/0 dev lo table $DEBUG_TPROXY_TABLE_ID

FWMARK_LOOPUP_TABLE_IDS=($(ip -4 rule show fwmark 0x1e/0x1f lookup $DEBUG_TPROXY_TABLE_ID | awk 'END {print $NF}'))
for TABLE_ID in ${FWMARK_LOOPUP_TABLE_IDS[@]}; do
  ip -4 rule delete fwmark 0x1e/0x1f lookup $TABLE_ID
  ip -4 route delete local 0.0.0.0/0 dev lo table $TABLE_ID
done

FWMARK_LOOPUP_TABLE_IDS=($(ip -6 rule show fwmark 0x1e/0x1f lookup $DEBUG_TPROXY_TABLE_ID | awk 'END {print $NF}'))
for TABLE_ID in ${FWMARK_LOOPUP_TABLE_IDS[@]}; do
  ip -6 rule delete fwmark 0x1e/0x1f lookup $TABLE_ID
  ip -6 route delete local ::/0 dev lo table $TABLE_ID
done
