#!/bin/bash

set -x

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)";

# This should run on if.up/if.down or
#   /etc/NetworkManager/dispatcher.d/up and /etc/NetworkManager/dispatcher.d/down , see man 8 NetworkManager

# Should be geater than SETUP_FWMARK_RULE_PRIORITY in v2ray
if [[ "x" == "x$SETUP_FWMARK_RULE_PRIORITY" ]]; then
    SETUP_FWMARK_RULE_PRIORITY=23001
fi

# Should be less than SETUP_FWMARK_RULE_PRIORITY
if [[ "x" == "x$SETUP_PPP_RULE_PRIORITY" ]]; then
    SETUP_PPP_RULE_PRIORITY=7101
fi

PPP_INTERFACES=($(ip -4 route show table main default | grep -E -o "ppp[0-9]+"));

bash "$SCRIPT_DIR/cleanup-multi-wan.sh" ;
if [[ ${#PPP_INTERFACES[@]} -lt 2 ]]; then
  exit;
fi
let SUM_WEIGHT=${#PPP_INTERFACES[@]}+2;

nft list table inet mwan > /dev/null 2>&1 ;
if [[ $? -ne 0 ]]; then
  nft add table inet mwan ;
else
  nft flush table inet mwan ;
fi

nft list chain inet mwan PREROUTING > /dev/null 2>&1 ;
if [[ $? -ne 0 ]]; then
  nft add chain inet mwan PREROUTING { type filter hook forward priority filter + 2 \; }
fi

nft list chain inet mwan OUTPUT > /dev/null 2>&1 ;
if [[ $? -ne 0 ]]; then
  nft add chain inet mwan OUTPUT { type route hook output priority filter + 2 \; }
fi

nft list chain inet mwan MARK > /dev/null 2>&1 ;
if [[ $? -ne 0 ]]; then
  nft add chain inet mwan MARK ;
fi

# Add rules to skip local address
nft add rule inet mwan MARK meta l4proto != {tcp, udp} return
nft add rule inet mwan MARK mark and 0xff00 != 0x0 return
nft add rule inet mwan MARK ip daddr {127.0.0.1/32, 224.0.0.0/4, 255.255.255.255/32} return
nft add rule inet mwan MARK ip daddr {192.168.0.0/16, 172.16.0.0/12, 10.0.0.0/8} return
nft add rule inet mwan MARK ip daddr {119.29.29.29/32, 223.5.5.5/32, 223.6.6.6/32, 180.76.76.76/32} return

nft add rule inet mwan MARK ip6 daddr {::1/128, fc00::/7, fe80::/10, ff00::/8} return
nft add rule inet mwan MARK ip6 daddr {2400:3200::1/128, 2400:3200:baba::1/128, 2400:da00::6666/128} return

PPP_INDEX=0;
for PPP_IF in ${PPP_INTERFACES[@]}; do
  let PPP_INDEX=$PPP_INDEX+1;
  nft add rule inet mwan MARK mark and 0xff00 == 0x0 symhash mod $SUM_WEIGHT == $PPP_INDEX meta mark set mark and 0xffff00ff xor "0x$(printf '%x' $PPP_INDEX)00" ;
  # Policy router only for not first ppp
  if [[ $PPP_INDEX -gt 1 ]]; then
    let TABLE_INDEX=100+$PPP_INDEX;
    TABLE_OPTIONS=($(ip -4 route show table main default | grep -E "dev[[:space:]]+ppp0"));
    RETRY_TIMES=0;
    ip -4 route add ${TABLE_OPTIONS[@]} table $TABLE_INDEX ;
    # TODO By hash fwmark: 0x100
    ip -4 rule add fwmark "0x$(printf '%x' $PPP_INDEX)00/0xff00" priority $SETUP_FWMARK_RULE_PRIORITY lookup $TABLE_INDEX ;
    while [[ $? -ne 0 ]] && [[ $RETRY_TIMES -lt 16 ]]; do
      let RETRY_TIMES=$RETRY_TIMES+1;
      let SETUP_FWMARK_RULE_PRIORITY=$SETUP_FWMARK_RULE_PRIORITY+1;
      ip -4 rule add fwmark "0x$(printf '%x' $PPP_INDEX)00/0xff00" priority $SETUP_FWMARK_RULE_PRIORITY lookup $TABLE_INDEX ;
    done
    let SETUP_FWMARK_RULE_PRIORITY=$SETUP_FWMARK_RULE_PRIORITY+1;
  fi

  # Policy router for ppp
  RETRY_TIMES=0;
  ip -4 rule add iif $PPP_IF priority $SETUP_PPP_RULE_PRIORITY lookup main ;
  while [[ $? -ne 0 ]] && [[ $RETRY_TIMES -lt 16 ]]; do
    let RETRY_TIMES=$RETRY_TIMES+1;
    let SETUP_PPP_RULE_PRIORITY=$SETUP_PPP_RULE_PRIORITY-1;
    ip -4 rule add iif $PPP_IF priority $SETUP_PPP_RULE_PRIORITY lookup main ;
  done
  let SETUP_PPP_RULE_PRIORITY=$SETUP_PPP_RULE_PRIORITY-1;
done

# nft add rule inet mwan MARK meta mark set ct mark and 0xff00
# # TODO By random fwmark: 0x100
# nft add rule inet mwan MARK mark and 0xff00 == 0x0 numgen random mod $SUM_WEIGHT == 0x1 meta mark set mark and 0xffff00ff xor 0x100
# nft add rule inet mwan MARK ct mark set mark and 0xff00


nft add rule inet PREROUTING goto MARK
nft add rule inet OUTPUT goto MARK
