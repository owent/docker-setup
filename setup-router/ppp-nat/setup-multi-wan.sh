#!/bin/bash

# set -x

if [[ -e "/opt/nftables/sbin" ]]; then
    export PATH=/opt/nftables/sbin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/bin/site_perl:/usr/bin/vendor_perl:/usr/bin/core_perl
else
    export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/bin/site_perl:/usr/bin/vendor_perl:/usr/bin/core_perl
fi

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)";

# nftables
# Quick: https://wiki.nftables.org/wiki-nftables/index.php/Performing_Network_Address_Translation_(NAT)
# Quick(CN): https://wiki.archlinux.org/index.php/Nftables_(%E7%AE%80%E4%BD%93%E4%B8%AD%E6%96%87)#Masquerading
# List all tables/chains/rules/matches/statements: https://wiki.nftables.org/wiki-nftables/index.php/Quick_reference-nftables_in_10_minutes#Rules
# man 8 nft: 
#    https://www.netfilter.org/projects/nftables/manpage.html
#    https://www.mankier.com/8/nft
# Note:
#     using ```find /lib/modules/$(uname -r) -type f -name '*.ko'``` to see all available modules
#     sample: https://wiki.archlinux.org/index.php/Simple_stateful_firewall#Setting_up_a_NAT_gateway
#     require kernel module: nft_nat, nft_chain_nat, xt_nat, nf_nat_ftp, nf_nat_tftp
# Netfilter: https://en.wikipedia.org/wiki/Netfilter
#            http://inai.de/images/nf-packet-flow.svg
# Monitor: nft monitor
#
# See https://openwrt.org/docs/guide-user/network/wan/multiwan/mwan3#overview_of_how_routing_with_mwan3_works
# This script should run on if.up/if.down
#   or /etc/NetworkManager/dispatcher.d/up,/etc/NetworkManager/dispatcher.d/down , see man 8 NetworkManager
#   or /etc/ppp/ip-up.d/98-setup-multi-wan.sh
#      /etc/ppp/ipv6-up.d/98-setup-multi-wan.sh,/etc/ppp/ipv6-down.d/98-setup-multi-wan.sh

if [[ "x" == "x$SETUP_WITH_DEBUG_LOG" ]]; then
    SETUP_WITH_DEBUG_LOG=0
fi

# Should be geater than SETUP_FWMARK_RULE_PRIORITY in v2ray
if [[ "x" == "x$SETUP_FWMARK_RULE_PRIORITY" ]]; then
    SETUP_FWMARK_RULE_PRIORITY=23001
fi

# Should be less than SETUP_FWMARK_RULE_PRIORITY
if [[ "x" == "x$SETUP_PPP_RULE_PRIORITY" ]]; then
    SETUP_PPP_RULE_PRIORITY=7101
fi
MAX_RETRY_TIMES=32;

if [[ ! -e "/run/multi-wan/ipv4" ]]; then
  # Fake create /run/multi-wan/ipv4
  mkdir -p /run/multi-wan/ ;
  chmod 777 /run/multi-wan/ ;
  touch /run/multi-wan/ipv4 ;
  chmod 777 /run/multi-wan/ipv4 ;
  for PPP_IF_NAME in $(ip -4 route show table main default | grep -E -o "ppp[0-9]+"); do
    PPP_ADDRS=($(ip -4 -o addr show dev $PPP_IF_NAME | grep -E -o '[0-9\]+\.[0-9\]+\.[0-9\]+\.[0-9\]+(/[0-9]+)?'));
    if [[ ${#PPP_ADDRS[@]} -gt 0 ]]; then
      echo "$PPP_IF_NAME IPLOCAL=\"${PPP_ADDRS[0]}\" IPREMOTE=\"${PPP_ADDRS[1]}\"" >> /run/multi-wan/ipv4 ;
    fi
  done
fi

PPP_INTERFACES_DB="$(cat /run/multi-wan/ipv4)";
PPP_INTERFACES_IPV4=($(echo "$PPP_INTERFACES_DB" | awk '{print $1}'));

bash "$SCRIPT_DIR/cleanup-multi-wan.sh" ;
if [[ ${#PPP_INTERFACES_IPV4[@]} -lt 2 ]]; then
  exit;
fi
let SUM_WEIGHT_IPV4=${#PPP_INTERFACES_IPV4[@]}+2;

function get_next_empty_table_id_ipv4() {
  TABLE_ID=$1;
  if [[ -z "$TABLE_ID" ]]; then
    TABLE_ID=101;
  fi
  while [[ $TABLE_ID -lt 250 ]]; do
    ip -4 route show table $TABLE_ID > /dev/null 2>&1;
    if [[ $? -ne 0 ]]; then
      echo "$TABLE_ID";
      return;
    fi
    RULE_COUNT=$(ip -4 route show table $TABLE_ID | wc -l);
    if [[ $RULE_COUNT -eq 0 ]]; then
      echo "$TABLE_ID";
      return;
    fi
    let TABLE_ID=$TABLE_ID+1;
  done
}

if [[ $(ip -4 rule list priority 1 lookup local | wc -l) -eq 0 ]]; then
  ip -4 rule add priority 1 lookup local ;
fi

if [[ $(ip -6 rule list priority 1 lookup local | wc -l) -eq 0 ]]; then
  ip -6 rule add priority 1 lookup local ;
fi

nft list table inet mwan > /dev/null 2>&1 ;
if [[ $? -ne 0 ]]; then
  nft add table inet mwan ;
else
  nft flush table inet mwan ;
fi

nft list chain inet mwan PREROUTING > /dev/null 2>&1 ;
if [[ $? -ne 0 ]]; then
  nft add chain inet mwan PREROUTING { type filter hook prerouting priority mangle \; }
else
  nft flush chain inet mwan PREROUTING ;
fi

nft list chain inet mwan OUTPUT > /dev/null 2>&1 ;
if [[ $? -ne 0 ]]; then
  nft add chain inet mwan OUTPUT { type route hook output priority mangle \; }
else
  nft flush chain inet mwan OUTPUT ;
fi

nft list chain inet mwan MARK > /dev/null 2>&1 ;
if [[ $? -ne 0 ]]; then
  nft add chain inet mwan MARK ;
else
  nft flush chain inet mwan MARK ;
fi

nft list chain inet mwan POLICY_MARK > /dev/null 2>&1 ;
if [[ $? -ne 0 ]]; then
  nft add chain inet mwan POLICY_MARK ;
else
  nft flush chain inet mwan POLICY_MARK ;
fi

# Add rules to skip local address
nft add rule inet mwan MARK meta l4proto != {tcp, udp} return

if [[ $SETUP_WITH_DEBUG_LOG -ne 0 ]]; then
  nft add rule inet mwan MARK ip daddr { 103.235.46.39, 180.101.49.11, 180.101.49.12 } meta nftrace set 1
  nft add rule inet mwan MARK ip daddr { 103.235.46.39, 180.101.49.11, 180.101.49.12 } log prefix '"===mwan===MARK:"' level debug flags all
fi

nft add rule inet mwan MARK meta mark and 0xff00 != 0x0 return
# Restore fwmark of last 8 bits into ct mark
nft add rule inet mwan MARK meta mark and 0xffff != 0x0 ct mark and 0xff00 == 0x0 ct mark set meta mark and 0xffff ;
# And then set last 9-16 bits in conntrack into packet
nft add rule inet mwan MARK meta mark and 0xff00 == 0x0 ct mark and 0xff00 != 0x0 meta mark set ct mark and 0xffff ;
nft add rule inet mwan MARK meta mark and 0xff00 != 0x0 return
nft add rule inet mwan MARK ip daddr {127.0.0.1/32, 224.0.0.0/4, 255.255.255.255/32} return
nft add rule inet mwan MARK ip daddr {192.168.0.0/16, 172.16.0.0/12, 10.0.0.0/8} return
nft add rule inet mwan MARK ip daddr {119.29.29.29/32, 223.5.5.5/32, 223.6.6.6/32, 180.76.76.76/32} return

nft add rule inet mwan MARK ip6 daddr {::1/128, fc00::/7, fe80::/10, ff00::/8} return
nft add rule inet mwan MARK ip6 daddr {2400:3200::1/128, 2400:3200:baba::1/128, 2400:da00::6666/128} return

if [[ $SETUP_WITH_DEBUG_LOG -ne 0 ]]; then
  nft add rule inet mwan MARK ip daddr 180.101.49.11 meta mark and 0xff00 != 0x0 meta mark set meta mark and 0xffff00ff xor 0x200
  nft add rule inet mwan MARK ip daddr 180.101.49.12 meta mark and 0xff00 != 0x0 meta mark set meta mark and 0xffff00ff xor 0xfe00
fi

PPP_INDEX=0;
TABLE_ID=100;
for PPP_IF_NAME in ${PPP_INTERFACES_IPV4[@]}; do
  EVAL_EXPR="$(echo "$PPP_INTERFACES_DB" | awk "\$1 == \"$PPP_IF_NAME\" { print \"IFNAME=\"\$0; }")" ;
  eval "$EVAL_EXPR";
  let PPP_INDEX=$PPP_INDEX+1;
  CURRENT_PPP_FWMARK="0x$(printf '%x' $PPP_INDEX)00";
  # Policy router only for not first ppp
  let LAST_ACTION_SUCCESS=0;

  if [[ ! -z "$IPLOCAL" ]]; then
    nft add rule inet mwan MARK meta mark and 0xff00 == 0x0 ip saddr "$IPLOCAL" meta mark set meta mark and 0xffff00ff xor 0xff00 ;
  fi
  if [[ ! -z "$IPREMOTE" ]]; then
    nft add rule inet mwan MARK meta mark and 0xff00 == 0x0 ip saddr "$IPREMOTE" meta mark set meta mark and 0xffff00ff xor 0xff00 ;
  fi

  let TABLE_ID=$TABLE_ID+1;
  TABLE_ID=$(get_next_empty_table_id_ipv4 $TABLE_ID);
  TABLE_OPTIONS=($(ip -4 route show table main default | grep -E "dev[[:space:]]+$PPP_IF_NAME"));
  RETRY_TIMES=0;
  # Route table
  ip -4 route add ${TABLE_OPTIONS[@]} table $TABLE_ID ;

  # Rule to fallback to main
  ip -4 rule add fwmark "$CURRENT_PPP_FWMARK/0xff00" priority $SETUP_FWMARK_RULE_PRIORITY lookup main suppress_prefixlength 0;
  LAST_ACTION_SUCCESS=$?;
  while [[ $LAST_ACTION_SUCCESS -ne 0 ]] && [[ $RETRY_TIMES -lt $MAX_RETRY_TIMES ]]; do
    let RETRY_TIMES=$RETRY_TIMES+1;
    let SETUP_FWMARK_RULE_PRIORITY=$SETUP_FWMARK_RULE_PRIORITY+1;
    ip -4 rule add fwmark "$CURRENT_PPP_FWMARK/0xff00" priority $SETUP_FWMARK_RULE_PRIORITY lookup main suppress_prefixlength 0;
    LAST_ACTION_SUCCESS=$?;
  done
  let SETUP_FWMARK_RULE_PRIORITY=$SETUP_FWMARK_RULE_PRIORITY+1;

  # Rule to policy to $PPP_IF_NAME, must be lower priority than before
  if [[ $LAST_ACTION_SUCCESS -eq 0 ]]; then
    ip -4 rule add fwmark "$CURRENT_PPP_FWMARK/0xff00" priority $SETUP_FWMARK_RULE_PRIORITY lookup $TABLE_ID ;
    LAST_ACTION_SUCCESS=$?;
    while [[ $LAST_ACTION_SUCCESS -ne 0 ]] && [[ $RETRY_TIMES -lt $MAX_RETRY_TIMES ]]; do
      let RETRY_TIMES=$RETRY_TIMES+1;
      let SETUP_FWMARK_RULE_PRIORITY=$SETUP_FWMARK_RULE_PRIORITY+1;
      ip -4 rule add fwmark "$CURRENT_PPP_FWMARK/0xff00" priority $SETUP_FWMARK_RULE_PRIORITY lookup $TABLE_ID ;
      LAST_ACTION_SUCCESS=$?;
    done
    let SETUP_FWMARK_RULE_PRIORITY=$SETUP_FWMARK_RULE_PRIORITY+1;
  fi

  # Policy set fwmark 
  if [[ $LAST_ACTION_SUCCESS -eq 0 ]]; then
    if [[ $SETUP_WITH_DEBUG_LOG -eq 0 ]]; then
      # By hash fwmark: 0x100
      nft add rule inet mwan POLICY_MARK meta mark and 0xff00 == 0x0 symhash mod $SUM_WEIGHT_IPV4 == $PPP_INDEX meta mark set meta mark and 0xffff00ff xor $CURRENT_PPP_FWMARK ;
    else
      # By random fwmark: 0x100
      nft add rule inet mwan POLICY_MARK meta mark and 0xff00 == 0x0 numgen random mod $SUM_WEIGHT_IPV4 == 0 meta mark set meta mark and 0xffff00ff xor $CURRENT_PPP_FWMARK ;
      let SUM_WEIGHT_IPV4=$SUM_WEIGHT_IPV4-1;
    fi
  fi
  
  # Policy router for ppp
  if [[ $LAST_ACTION_SUCCESS -eq 0 ]]; then
    RETRY_TIMES=0;
    ip -4 rule add iif $PPP_IF_NAME priority $SETUP_PPP_RULE_PRIORITY lookup main ;
    LAST_ACTION_SUCCESS=$?;
    while [[ $LAST_ACTION_SUCCESS -ne 0 ]] && [[ $RETRY_TIMES -lt $MAX_RETRY_TIMES ]]; do
      let RETRY_TIMES=$RETRY_TIMES+1;
      let SETUP_PPP_RULE_PRIORITY=$SETUP_PPP_RULE_PRIORITY-1;
      ip -4 rule add iif $PPP_IF_NAME priority $SETUP_PPP_RULE_PRIORITY lookup main ;
      LAST_ACTION_SUCCESS=$?;
    done
    let SETUP_PPP_RULE_PRIORITY=$SETUP_PPP_RULE_PRIORITY-1;
  fi
done

# Balance policy
nft add rule inet mwan MARK meta mark and 0xff00 == 0x0 jump POLICY_MARK ;

# Force set fwmark in case of change router later
nft add rule inet mwan MARK meta mark and 0xff00 == 0x0 meta mark set meta mark and 0xffff00ff xor 0xfe00 ;
nft add rule inet mwan MARK ct mark set meta mark and 0xffff ;

nft add rule inet mwan PREROUTING jump MARK
nft add rule inet mwan OUTPUT jump MARK
