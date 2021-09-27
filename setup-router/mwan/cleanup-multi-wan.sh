#!/bin/bash

# set -x

if [[ -e "/opt/nftables/sbin" ]]; then
  export PATH=/opt/nftables/sbin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/bin/site_perl:/usr/bin/vendor_perl:/usr/bin/core_perl
else
  export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/bin/site_perl:/usr/bin/vendor_perl:/usr/bin/core_perl
fi

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"

source "$SCRIPT_DIR/setup-multi-wan-conf.sh"

# Remove iface rules
IP_RULE_LOOPUP_TABLE_IIFACES_IPV4=($(ip -4 rule show | grep -E -o "iif[[:space:]]+([0-9A-Za-z_-]+)" | awk '{print $NF}'))
for IFACE_IPV4 in ${IP_RULE_LOOPUP_TABLE_IIFACES_IPV4[@]}; do
  mwan_not_in_watch_list "$IFACE_IPV4" || ip -4 rule delete iif $IFACE_IPV6 lookup main
done

IP_RULE_LOOPUP_TABLE_IIFACES_IPV6=($(ip -6 rule show | grep -E -o "iif[[:space:]]+([0-9A-Za-z_-]+)" | awk '{print $NF}'))
for IFACE_IPV6 in ${IP_RULE_LOOPUP_TABLE_IIFACES_IPV6[@]}; do
  mwan_not_in_watch_list "$IFACE_IPV6" || ip -6 rule delete iif $IFACE_IPV6 lookup main
done

# Remove fwmark rules
function mwan_remove_fwmark_rules() {
  IP_RULE_LOOPUP_TABLE_FWMARK=($(ip "$@" rule show | grep -E -o "fwmark 0x.*/0xff00" | awk '{print $NF}'))
  IP_RULE_LOOPUP_TABLE_IDS=()
  for PPP_FWMARK in ${IP_RULE_LOOPUP_TABLE_FWMARK[@]}; do
    TABLE_IDS=($(ip "$@" rule show | grep -E "fwmark[[:space:]]+$PPP_FWMARK" | grep -E -o "lookup[[:space:]](.*)" | awk '{print $NF}'))
    ip "$@" rule delete fwmark $PPP_FWMARK

    # Cleanup ip route table
    for TABLE_ID in ${TABLE_IDS[@]}; do
      if [[ ! -z "$TABLE_ID" ]] && [[ "$TABLE_ID" != "main" ]] && [[ "$TABLE_ID" != "local" ]] && [[ "$TABLE_ID" != "default" ]] \
        && [[ "$TABLE_ID" != "253" ]] && [[ "$TABLE_ID" != "254" ]] && [[ "$TABLE_ID" != "255" ]] && [[ "$TABLE_ID" != "0" ]]; then
        IP_RULE_LOOPUP_TABLE_IDS=(${IP_RULE_LOOPUP_TABLE_IDS[@]} $TABLE_ID)
      fi
    done
  done

  for TABLE_ID in ${IP_RULE_LOOPUP_TABLE_IDS[@]}; do
    ip "$@" route flush table $TABLE_ID
  done
}

# Remove iif rules
function mwan_remove_iif_rules() {
  for MWAN_IF_NAME in ${MWAN_WATCH_INERFACES[@]}; do
    ip "$@" rule del iif $MWAN_IF_NAME lookup main >/dev/null 2>&1
    while [[ $? -eq 0 ]]; do
      ip "$@" rule del iif $MWAN_IF_NAME lookup main >/dev/null 2>&1
    done
  done
}

mwan_remove_fwmark_rules "-4"
mwan_remove_fwmark_rules "-6"
mwan_remove_iif_rules "-4"
mwan_remove_iif_rules "-6"

# Remove net_fitler
nft list table inet mwan >/dev/null 2>&1
if [[ $? -eq 0 ]]; then
  nft delete table inet mwan
fi
