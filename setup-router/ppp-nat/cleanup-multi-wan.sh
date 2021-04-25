#!/bin/bash

# set -x

if [[ -e "/opt/nftables/sbin" ]]; then
    export PATH=/opt/nftables/sbin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/bin/site_perl:/usr/bin/vendor_perl:/usr/bin/core_perl
else
    export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/bin/site_perl:/usr/bin/vendor_perl:/usr/bin/core_perl
fi

# Remove ppp rules
TRY_DELETE_PPP_INDEX=0;
IP_RULE_LOOPUP_TABLE_IIF_PPP=($(ip -4 rule show | grep -E -o "iif[[:space:]]+(ppp[0-9]+)" | awk '{print $NF}'));
for PPP_IF_NAME in ${IP_RULE_LOOPUP_TABLE_IIF_PPP[@]}; do
  ip -4 rule delete iif $PPP_IF_NAME lookup main ;
done

# Remove fwmark rules
TRY_DELETE_FWMARK_INDEX=1;
IP_RULE_LOOPUP_TABLE_FWMARK_PPP=($(ip -4 rule show | grep -E -o "fwmark 0x.*/0xff00" | awk '{print $NF}'));
PPP_TABLE_IDS=()
for PPP_FWMARK in ${IP_RULE_LOOPUP_TABLE_FWMARK_PPP[@]}; do
  TABLE_IDS=($(ip -4 rule show | grep -E "fwmark[[:space:]]+$PPP_FWMARK" | grep -E -o "lookup[[:space:]](.*)" | awk '{print $NF}'));
  ip -4 rule delete fwmark $PPP_FWMARK ;

  # Cleanup ip route table
  for TABLE_ID in ${TABLE_IDS[@]}; do
    if [[ ! -z "$TABLE_ID" ]] && [[ "$TABLE_ID" != "main" ]] && [[ "$TABLE_ID" != "local" ]] && [[ "$TABLE_ID" != "default" ]] &&
      [[ "$TABLE_ID" != "253" ]] && [[ "$TABLE_ID" != "254" ]] && [[ "$TABLE_ID" != "255" ]] && [[ "$TABLE_ID" != "0" ]]; then
      PPP_TABLE_IDS=(${PPP_TABLE_IDS[@]} $TABLE_ID);
    fi
  done
done

for TABLE_ID in ${PPP_TABLE_IDS[@]}; do
  ip -4 route flush table $TABLE_ID ;
done

# Remove net_fitler
nft list table inet mwan > /dev/null 2>&1 ;
if [[ $? -eq 0 ]]; then
  nft delete table inet mwan ;
fi
