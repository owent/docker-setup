#!/bin/bash

# set -x

if [[ -e "/opt/nftables/sbin" ]]; then
  export PATH=/opt/nftables/sbin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/bin/site_perl:/usr/bin/vendor_perl:/usr/bin/core_perl
else
  export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/bin/site_perl:/usr/bin/vendor_perl:/usr/bin/core_perl
fi

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"

source "$SCRIPT_DIR/setup-multi-wan-conf.sh"

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
if [[ "x" == "x$SETUP_MWAN_RULE_PRIORITY" ]]; then
  SETUP_MWAN_RULE_PRIORITY=7101
fi
MAX_RETRY_TIMES=32

MWAN_INTERFACES_IPV4=( )
for MWAN_CHECK_INTERFACE_NAME in $(ip -4 -o addr show scope global | awk '{ print $2 }' | uniq); do
  MWAN_CHECK_INTERFACE_SUCCESS=0
  for MWAN_WATCH_INTERFACE_NAME in ${MWAN_WATCH_INERFACES[@]}; do
    if [[ "$MWAN_CHECK_INTERFACE_NAME" == "$MWAN_WATCH_INTERFACE_NAME" ]]; then
      MWAN_CHECK_INTERFACE_SUCCESS=1
      break
    fi
  done
  if [[ $MWAN_CHECK_INTERFACE_SUCCESS -ne 0 ]]; then
    MWAN_INTERFACES_IPV4=(${MWAN_INTERFACES_IPV4[@]} $MWAN_CHECK_INTERFACE_NAME)
  fi
done

echo "============ ip -4 -o addr show scope global ============"
ip -4 -o addr show scope global
echo "MWAN_INTERFACES_IPV4=${MWAN_INTERFACES_IPV4[@]}"

MWAN_INTERFACES_IPV6=( )
for MWAN_CHECK_INTERFACE_NAME in $(ip -6 -o addr show scope global | awk '{ print $2 }' | uniq); do
  MWAN_CHECK_INTERFACE_SUCCESS=0
  for MWAN_WATCH_INTERFACE_NAME in ${MWAN_WATCH_INERFACES[@]}; do
    if [[ "$MWAN_CHECK_INTERFACE_NAME" == "$MWAN_WATCH_INTERFACE_NAME" ]]; then
      MWAN_CHECK_INTERFACE_SUCCESS=1
      break
    fi
  done
  if [[ $MWAN_CHECK_INTERFACE_SUCCESS -ne 0 ]]; then
    MWAN_INTERFACES_IPV6=(${MWAN_INTERFACES_IPV6[@]} $MWAN_CHECK_INTERFACE_NAME)
  fi
done
echo "============ ip -6 -o addr show scope global ============"
ip -6 -o addr show scope global
echo "MWAN_INTERFACES_IPV6=${MWAN_INTERFACES_IPV6[@]}"

bash "$SCRIPT_DIR/cleanup-multi-wan.sh"
if [[ ${#MWAN_INTERFACES_IPV4[@]} -lt 2 ]] && [[ ${#MWAN_INTERFACES_IPV6[@]} -lt 2 ]]; then
  exit
fi

function get_next_empty_table_id_ip() {
  TABLE_ID=$2
  if [[ -z "$TABLE_ID" ]]; then
    TABLE_ID=101
  fi
  while [[ $TABLE_ID -lt 250 ]]; do
    ip $1 route show table $TABLE_ID >/dev/null 2>&1
    if [[ $? -ne 0 ]]; then
      echo "$TABLE_ID"
      return
    fi
    RULE_COUNT=$(ip $1 route show table $TABLE_ID | wc -l)
    if [[ $RULE_COUNT -eq 0 ]]; then
      echo "$TABLE_ID"
      return
    fi
    let TABLE_ID=$TABLE_ID+1
  done
}

if [[ $(ip -4 rule list priority 1 lookup local | wc -l) -eq 0 ]]; then
  ip -4 rule add priority 1 lookup local
fi

if [[ $(ip -6 rule list priority 1 lookup local | wc -l) -eq 0 ]]; then
  ip -6 rule add priority 1 lookup local
fi

nft list table inet mwan >/dev/null 2>&1
if [[ $? -ne 0 ]]; then
  nft add table inet mwan
else
  nft flush table inet mwan
fi

nft list chain inet mwan PREROUTING >/dev/null 2>&1
if [[ $? -ne 0 ]]; then
  nft add chain inet mwan PREROUTING { type filter hook prerouting priority mangle \; }
else
  nft flush chain inet mwan PREROUTING
fi

nft list chain inet mwan OUTPUT >/dev/null 2>&1
if [[ $? -ne 0 ]]; then
  nft add chain inet mwan OUTPUT { type route hook output priority mangle \; }
else
  nft flush chain inet mwan OUTPUT
fi

nft list chain inet mwan MARK >/dev/null 2>&1
if [[ $? -ne 0 ]]; then
  nft add chain inet mwan MARK
else
  nft flush chain inet mwan MARK
fi

nft list chain inet mwan POLICY_MARK >/dev/null 2>&1
if [[ $? -ne 0 ]]; then
  nft add chain inet mwan POLICY_MARK
else
  nft flush chain inet mwan POLICY_MARK
fi

nft list set inet mwan LOCAL_IPV4 >/dev/null 2>&1
if [[ $? -ne 0 ]]; then
  nft add set inet mwan LOCAL_IPV4 '{ type ipv4_addr; flags interval; auto-merge ; }'
  nft add element inet mwan LOCAL_IPV4 {127.0.0.1/32, 169.254.0.0/16, 192.168.0.0/16, 172.16.0.0/12, 10.0.0.0/8}
fi
nft list set inet mwan DEFAULT_ROUTE_IPV4 >/dev/null 2>&1
if [[ $? -ne 0 ]]; then
  nft add set inet mwan DEFAULT_ROUTE_IPV4 '{ type ipv4_addr; flags interval; auto-merge ; }'
fi

nft list set inet mwan LOCAL_IPV6 >/dev/null 2>&1
if [[ $? -ne 0 ]]; then
  nft add set inet mwan LOCAL_IPV6 '{ type ipv6_addr; flags interval; auto-merge ; }'
  nft add element inet mwan LOCAL_IPV6 {::1/128, fc00::/7, fe80::/10}
fi
nft list set inet mwan DEFAULT_ROUTE_IPV6 >/dev/null 2>&1
if [[ $? -ne 0 ]]; then
  nft add set inet mwan DEFAULT_ROUTE_IPV6 '{ type ipv6_addr; flags interval; auto-merge ; }'
fi

# Add rules to skip local address
nft add rule inet mwan MARK meta l4proto != {tcp, udp} return

if [[ $SETUP_WITH_DEBUG_LOG -ne 0 ]]; then
  nft add rule inet mwan MARK ip daddr { 103.235.46.39, 180.101.49.11, 180.101.49.12 } meta nftrace set 1
  nft add rule inet mwan MARK ip daddr { 103.235.46.39, 180.101.49.11, 180.101.49.12 } log prefix '"===mwan===MARK:"' level debug flags all
fi

nft add rule inet mwan MARK meta mark and 0xff00 != 0x0 return
# Restore fwmark of last 8 bits into ct mark
# nft add rule inet mwan MARK meta mark and 0xffff != 0x0 ct mark and 0xff00 == 0x0 ct mark set meta mark and 0xffff
# And then set last 9-16 bits in conntrack into packet
# nft add rule inet mwan MARK meta mark and 0xff00 == 0x0 ct mark and 0xff00 != 0x0 meta mark set ct mark and 0xffff
nft add rule inet mwan MARK ct mark and 0xff00 != 0x0 meta mark set ct mark and 0xffff
nft add rule inet mwan MARK meta mark and 0xff00 != 0x0 return
nft add rule inet mwan MARK ip daddr {224.0.0.0/4, 255.255.255.255/32} return
nft add rule inet mwan MARK ip daddr @LOCAL_IPV4 return
nft add rule inet mwan MARK ip daddr @DEFAULT_ROUTE_IPV4 return
nft add rule inet mwan MARK ip daddr '{ 172.20.1.1/24 }' return # 172.20.1.1/24 is used for remote debug
nft add rule inet mwan MARK ip daddr {119.29.29.29/32, 223.5.5.5/32, 223.6.6.6/32, 180.76.76.76/32} return

nft add rule inet mwan MARK ip6 daddr {ff00::/8} return
nft add rule inet mwan MARK ip6 daddr @LOCAL_IPV6 return
nft add rule inet mwan MARK ip6 daddr @DEFAULT_ROUTE_IPV6 return
nft add rule inet mwan MARK ip6 daddr {2400:3200::1/128, 2400:3200:baba::1/128, 2400:da00::6666/128} return

if [[ $SETUP_WITH_DEBUG_LOG -ne 0 ]]; then
  nft add rule inet mwan MARK ip daddr 180.101.49.11 meta mark and 0xff00 != 0x0 meta mark set meta mark and 0xffff00ff xor 0x200
  nft add rule inet mwan MARK ip daddr 180.101.49.12 meta mark and 0xff00 != 0x0 meta mark set meta mark and 0xffff00ff xor 0xfe00
fi

function mwan_setup_policy() {
  if [[ "x$1" == "xipv4" ]]; then
    MWAN_IPTYPE_PARAM="-4"
    MWAN_NFTABLE_IPTYPE_PARAM="ip"
    MWAN_IP_MATCH="[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+"
    MWAN_INTERFACES_CURRENT_IFACES=(${MWAN_INTERFACES_IPV4[@]})
  elif [[ "x$1" == "xipv6" ]]; then
    MWAN_IPTYPE_PARAM="-6"
    MWAN_NFTABLE_IPTYPE_PARAM="ip6"
    MWAN_IP_MATCH="[0-9a-fA-F:]+"
    MWAN_INTERFACES_CURRENT_IFACES=(${MWAN_INTERFACES_IPV6[@]})
  else
    return
  fi
  # Policy for local route
  LOCAL_ROUTE_TABLE=""
  for LOCAL_ROUTE_PREFIX in $(ip $MWAN_IPTYPE_PARAM route show | awk '{print $1}' | grep -E "$MWAN_IP_MATCH(/[0-9]+)?"); do
    if [[ -z "$LOCAL_ROUTE_TABLE" ]]; then
      LOCAL_ROUTE_TABLE="{$LOCAL_ROUTE_PREFIX"
    else
      LOCAL_ROUTE_TABLE="$LOCAL_ROUTE_TABLE, $LOCAL_ROUTE_PREFIX"
    fi
  done
  if [[ ! -z "$LOCAL_ROUTE_TABLE" ]]; then
    LOCAL_ROUTE_TABLE="$LOCAL_ROUTE_TABLE}"
    # nft add rule inet mwan MARK meta mark and 0xff00 == 0x0 $MWAN_NFTABLE_IPTYPE_PARAM saddr "$LOCAL_ROUTE_TABLE" meta mark set meta mark and 0xffff00ff xor 0xff00 ;
  fi

  MWAN_INDEX=0
  TABLE_ID=120
  let MWAN_SUM_WEIGHT=0
  for ((i = 0; i < ${#MWAN_WATCH_INERFACES[@]}; ++i)); do
    MWAN_TEST_IF_NAME=${MWAN_WATCH_INERFACES[$i]}
    MWAN_TEST_IF_SUCCESS=0
    for MWAN_ACTIVE_IF_NAME in ${MWAN_INTERFACES_CURRENT_IFACES[@]}; do
      if [[ "$MWAN_ACTIVE_IF_NAME" == "$MWAN_TEST_IF_NAME" ]]; then
        MWAN_TEST_IF_SUCCESS=1
        break
      fi
    done

    MWAN_CURRENT_IF_WEIGHT=${MWAN_INERFACES_WEIGHT[$i]}
    ip $MWAN_IPTYPE_PARAM route show table main default | grep -E "dev[[:space:]]+$MWAN_TEST_IF_NAME"
    TABLE_OPTIONS=($(ip $MWAN_IPTYPE_PARAM route show table main default | grep -E "dev[[:space:]]+$MWAN_TEST_IF_NAME"))
    if [[ $MWAN_TEST_IF_SUCCESS -eq 0 ]] || [[ $MWAN_CURRENT_IF_WEIGHT -le 0 ]] || [[ ${#TABLE_OPTIONS[@]} -le 0 ]]; then
      continue
    fi
    let MWAN_SUM_WEIGHT=$MWAN_SUM_WEIGHT+$MWAN_CURRENT_IF_WEIGHT
  done
  let MWAN_CURRENT_SUM_WEIGHT=0
  for ((i = 0; $i < ${#MWAN_WATCH_INERFACES[@]}; ++i)); do
    MWAN_IF_NAME=${MWAN_WATCH_INERFACES[$i]}
    MWAN_TEST_IF_SUCCESS=0
    for MWAN_ACTIVE_IF_NAME in ${MWAN_INTERFACES_CURRENT_IFACES[@]}; do
      if [[ "$MWAN_ACTIVE_IF_NAME" == "$MWAN_IF_NAME" ]]; then
        MWAN_TEST_IF_SUCCESS=1
        break
      fi
    done

    MWAN_CURRENT_IF_WEIGHT=${MWAN_INERFACES_WEIGHT[$i]}
    TABLE_OPTIONS_STR="$(ip $MWAN_IPTYPE_PARAM route show table main default)"
    if [[ "$TABLE_OPTIONS_STR" =~ "metric" ]]; then
      TABLE_OPTIONS_STR="$(echo "$TABLE_OPTIONS_STR" | grep -o -E '.*metric[[:space:]]+[0-9]+')"
    fi
    TABLE_OPTIONS=($(echo "$TABLE_OPTIONS_STR" | grep -E "dev[[:space:]]+$MWAN_IF_NAME"))
    if [[ $MWAN_TEST_IF_SUCCESS -eq 0 ]] || [[ $MWAN_CURRENT_IF_WEIGHT -le 0 ]] || [[ ${#TABLE_OPTIONS[@]} -le 0 ]]; then
      continue
    fi
    echo "Select ip $MWAN_IPTYPE_PARAM route for $MWAN_IF_NAME (Weight: $MWAN_CURRENT_IF_WEIGHT/$MWAN_SUM_WEIGHT): ${TABLE_OPTIONS[@]}"

    let MWAN_INDEX=$MWAN_INDEX+1
    let MWAN_CURRENT_SUM_WEIGHT=$MWAN_CURRENT_SUM_WEIGHT+$MWAN_CURRENT_IF_WEIGHT
    CURRENT_MWAN_FWMARK="0x$(printf '%x' $MWAN_INDEX)00"
    let LAST_ACTION_SUCCESS=0

    let TABLE_ID=$TABLE_ID+1
    TABLE_ID=$(get_next_empty_table_id_ip "$MWAN_IPTYPE_PARAM" $TABLE_ID)
    RETRY_TIMES=0
    # Route table
    ip $MWAN_IPTYPE_PARAM route add ${TABLE_OPTIONS[@]} table $TABLE_ID

    # Rule to fallback to main
    ip $MWAN_IPTYPE_PARAM rule add fwmark "$CURRENT_MWAN_FWMARK/0xff00" priority $SETUP_FWMARK_RULE_PRIORITY lookup main suppress_prefixlength 0
    LAST_ACTION_SUCCESS=$?
    while [[ $LAST_ACTION_SUCCESS -ne 0 ]] && [[ $RETRY_TIMES -lt $MAX_RETRY_TIMES ]]; do
      let RETRY_TIMES=$RETRY_TIMES+1
      let SETUP_FWMARK_RULE_PRIORITY=$SETUP_FWMARK_RULE_PRIORITY+1
      ip $MWAN_IPTYPE_PARAM rule add fwmark "$CURRENT_MWAN_FWMARK/0xff00" priority $SETUP_FWMARK_RULE_PRIORITY lookup main suppress_prefixlength 0
      LAST_ACTION_SUCCESS=$?
    done
    let SETUP_FWMARK_RULE_PRIORITY=$SETUP_FWMARK_RULE_PRIORITY+1

    # Rule to policy to $MWAN_IF_NAME, must be lower priority than before
    if [[ $LAST_ACTION_SUCCESS -eq 0 ]]; then
      ip $MWAN_IPTYPE_PARAM rule add fwmark "$CURRENT_MWAN_FWMARK/0xff00" priority $SETUP_FWMARK_RULE_PRIORITY lookup $TABLE_ID
      LAST_ACTION_SUCCESS=$?
      while [[ $LAST_ACTION_SUCCESS -ne 0 ]] && [[ $RETRY_TIMES -lt $MAX_RETRY_TIMES ]]; do
        let RETRY_TIMES=$RETRY_TIMES+1
        let SETUP_FWMARK_RULE_PRIORITY=$SETUP_FWMARK_RULE_PRIORITY+1
        ip $MWAN_IPTYPE_PARAM rule add fwmark "$CURRENT_MWAN_FWMARK/0xff00" priority $SETUP_FWMARK_RULE_PRIORITY lookup $TABLE_ID
        LAST_ACTION_SUCCESS=$?
      done
      let SETUP_FWMARK_RULE_PRIORITY=$SETUP_FWMARK_RULE_PRIORITY+1
    fi

    # Policy packages already has decision
    LOCAL_IP_ADDR_SET=""
    for LOCAL_IP_ADDR in $(ip $MWAN_IPTYPE_PARAM -o addr show $MWAN_IF_NAME | grep -E -o "inet[0-9]*[[:space:]]+$MWAN_IP_MATCH(/[0-9]+)?" | awk '{print $NF}'); do
      if [[ -z "$LOCAL_IP_ADDR_SET" ]]; then
        LOCAL_IP_ADDR_SET="{$LOCAL_IP_ADDR"
      else
        LOCAL_IP_ADDR_SET="$LOCAL_IP_ADDR_SET, $LOCAL_IP_ADDR"
      fi
    done
    if [[ ! -z "$LOCAL_IP_ADDR_SET" ]]; then
      LOCAL_IP_ADDR_SET="$LOCAL_IP_ADDR_SET}"
      nft add rule inet mwan MARK meta mark and 0xff00 == 0x0 $MWAN_NFTABLE_IPTYPE_PARAM saddr "$LOCAL_IP_ADDR_SET" meta mark set meta mark and 0xffff00ff xor 0xff00
    fi

    # Policy set fwmark
    if [[ $LAST_ACTION_SUCCESS -eq 0 ]]; then
      if [[ $SETUP_WITH_DEBUG_LOG -eq 0 ]]; then
        # By hash fwmark: 0x100
        if [[ $MWAN_SUM_WEIGHT -gt $MWAN_CURRENT_SUM_WEIGHT ]]; then
          # nft add rule inet mwan POLICY_MARK meta mark and 0xff00 == 0x0 symhash mod $MWAN_SUM_WEIGHT "<" $MWAN_CURRENT_SUM_WEIGHT meta mark set meta mark and 0xffff00ff xor $CURRENT_MWAN_FWMARK "return"
          nft add rule inet mwan POLICY_MARK meta mark and 0xff00 == 0x0 jhash ip daddr mod $MWAN_SUM_WEIGHT "<" $MWAN_CURRENT_SUM_WEIGHT meta mark set meta mark and 0xffff00ff xor $CURRENT_MWAN_FWMARK "return"
          nft add rule inet mwan POLICY_MARK meta mark and 0xff00 == 0x0 jhash ip6 daddr mod $MWAN_SUM_WEIGHT "<" $MWAN_CURRENT_SUM_WEIGHT meta mark set meta mark and 0xffff00ff xor $CURRENT_MWAN_FWMARK "return"
        else
          nft add rule inet mwan POLICY_MARK meta mark and 0xff00 == 0x0 meta mark set meta mark and 0xffff00ff xor $CURRENT_MWAN_FWMARK "return"
        fi
      else
        # By random fwmark: 0x100
        if [[ $MWAN_SUM_WEIGHT -gt $MWAN_CURRENT_SUM_WEIGHT ]]; then
          nft add rule inet mwan POLICY_MARK meta mark and 0xff00 == 0x0 numgen random mod $MWAN_SUM_WEIGHT "<" $MWAN_CURRENT_IF_WEIGHT meta mark set meta mark and 0xffff00ff xor $CURRENT_MWAN_FWMARK
        else
          nft add rule inet mwan POLICY_MARK meta mark and 0xff00 == 0x0 meta mark set meta mark and 0xffff00ff xor $CURRENT_MWAN_FWMARK
        fi
        let MWAN_SUM_WEIGHT=$MWAN_SUM_WEIGHT-$MWAN_CURRENT_SUM_WEIGHT
      fi
    fi

    # Policy router
    if [[ $LAST_ACTION_SUCCESS -eq 0 ]]; then
      RETRY_TIMES=0
      ip $MWAN_IPTYPE_PARAM rule del iif $MWAN_IF_NAME lookup main >/dev/null 2>&1
      while [[ $? -eq 0 ]]; do
        ip $MWAN_IPTYPE_PARAM rule del iif $MWAN_IF_NAME lookup main >/dev/null 2>&1
      done

      ip $MWAN_IPTYPE_PARAM rule add iif $MWAN_IF_NAME priority $SETUP_MWAN_RULE_PRIORITY lookup main
      LAST_ACTION_SUCCESS=$?
      while [[ $LAST_ACTION_SUCCESS -ne 0 ]] && [[ $RETRY_TIMES -lt $MAX_RETRY_TIMES ]]; do
        let RETRY_TIMES=$RETRY_TIMES+1
        let SETUP_MWAN_RULE_PRIORITY=$SETUP_MWAN_RULE_PRIORITY-1
        ip $MWAN_IPTYPE_PARAM rule add iif $MWAN_IF_NAME priority $SETUP_MWAN_RULE_PRIORITY lookup main
        LAST_ACTION_SUCCESS=$?
      done
      let SETUP_MWAN_RULE_PRIORITY=$SETUP_MWAN_RULE_PRIORITY-1
    fi
  done
}

if [[ ${#MWAN_INTERFACES_IPV4[@]} -ge 2 ]]; then
  mwan_setup_policy ipv4
fi

if [[ ${#MWAN_INTERFACES_IPV6[@]} -ge 2 ]]; then
  mwan_setup_policy ipv6
fi

# Balance policy
nft add rule inet mwan MARK meta mark and 0xff00 == 0x0 jump POLICY_MARK

# Force set fwmark in case of change router later
nft add rule inet mwan MARK meta mark and 0xff00 == 0x0 meta mark set meta mark and 0xffff00ff xor 0xfe00
nft add rule inet mwan MARK ct mark set meta mark and 0xffff

nft add rule inet mwan PREROUTING jump MARK
nft add rule inet mwan OUTPUT jump MARK
