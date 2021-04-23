#!/bin/bash

set -x

# Remove ppp rules
TRY_DELETE_PPP_INDEX=0;
IP_RULE_LOOPUP_TABLE_IIF_PPP=($(ip -4 rule show | grep -E -o "iif[[:space:]]+(ppp[0-9]+)" | awk '{print $NF}'));
for PPP_IF in ${IP_RULE_LOOPUP_TABLE_IIF_PPP[@]}; do
  ip -4 rule delete iif $PPP_IF;
done

# Remove fwmark rules
TRY_DELETE_FWMARK_INDEX=1;
IP_RULE_LOOPUP_TABLE_FWMARK_PPP=$(ip -4 rule show | grep -E -o "fwmark 0x.*/0xff00" | awk '{print $NF}');
for PPP_FWMARK in ${IP_RULE_LOOPUP_TABLE_FWMARK_PPP[@]}; do
  TABLE_ID=$(ip -4 rule show | grep -E "fwmark[[:space:]]+$PPP_FWMARK" | grep -E -o "lookup[[:space:]](.*)" | awk '{print $NF}');
  ip -4 rule delete fwmark $PPP_FWMARK ;

  # Cleanup ip route table
  ip -4 route del table $TABLE_ID ;
done

# Remove net_fitler
nft list table inet mwan > /dev/null 2>&1 ;
if [[ $? -eq 0 ]]; then
  nft delete table inet mwan ;
fi
