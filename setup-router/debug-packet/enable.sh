#!/bin/bash

#### ========== debug ==========
#### Use nft monitor trace to see the packet trace
DEBUG_WATCH_IPV4_DADDR=()
DEBUG_WATCH_IPV4_SADDR=(${DEBUG_WATCH_IPV4_DADDR[@]})

DEBUG_WATCH_IPV6_DADDR=() #(2402:4e00:: 2400:3200:baba::1)
DEBUG_WATCH_IPV6_SADDR=() #(${DEBUG_WATCH_IP6_DADDR[@]})

DEBUG_TPROXY_IPV4_ADDR=()
DEBUG_TPROXY_IPV6_ADDR=()
DEBUG_TPROXY_TABLE_ID=89
DEBUG_TPROXY_PORT=3371
DEBUG_FWMARK_RULE_PRIORITY=9991

function init_debug_ip_sets() {
  FAMILY_NAME="$1"

  nft list set $FAMILY_NAME debug WATCH_IPV4_DADDR >/dev/null 2>&1
  if [[ $? -ne 0 ]]; then
    nft add set $FAMILY_NAME debug WATCH_IPV4_DADDR '{ type ipv4_addr; flags interval; auto-merge ; }'
  fi
  nft flush set $FAMILY_NAME debug WATCH_IPV4_DADDR
  for ip in ${DEBUG_WATCH_IPV4_DADDR[@]}; do
    nft add element $FAMILY_NAME debug WATCH_IPV4_DADDR "{ $ip }"
  done
  nft list set $FAMILY_NAME debug WATCH_IPV4_SADDR >/dev/null 2>&1
  if [[ $? -ne 0 ]]; then
    nft add set $FAMILY_NAME debug WATCH_IPV4_SADDR '{ type ipv4_addr; flags interval; auto-merge ; }'
  fi
  nft flush set $FAMILY_NAME debug WATCH_IPV4_SADDR
  for ip in ${DEBUG_WATCH_IPV4_SADDR[@]}; do
    nft add element $FAMILY_NAME debug WATCH_IPV4_SADDR "{ $ip }"
  done

  nft list set $FAMILY_NAME debug WATCH_TPROXY_IPV4_ADDR >/dev/null 2>&1
  if [[ $? -ne 0 ]]; then
    nft add set $FAMILY_NAME debug WATCH_TPROXY_IPV4_ADDR '{ type ipv4_addr; flags interval; auto-merge ; }'
  fi
  nft flush set $FAMILY_NAME debug WATCH_TPROXY_IPV4_ADDR
  for ip in ${DEBUG_TPROXY_IPV4_ADDR[@]}; do
    nft add element $FAMILY_NAME debug WATCH_TPROXY_IPV4_ADDR "{ $ip }"
  done

  nft list set $FAMILY_NAME debug WATCH_IPV6_DADDR >/dev/null 2>&1
  if [[ $? -ne 0 ]]; then
    nft add set $FAMILY_NAME debug WATCH_IPV6_DADDR '{ type ipv6_addr; flags interval; auto-merge ; }'
  fi
  nft flush set $FAMILY_NAME debug WATCH_IPV6_DADDR
  for ip in ${DEBUG_WATCH_IPV6_DADDR[@]}; do
    nft add element $FAMILY_NAME debug WATCH_IPV6_DADDR "{ $ip }"
  done
  nft list set $FAMILY_NAME debug WATCH_IPV6_SADDR >/dev/null 2>&1
  if [[ $? -ne 0 ]]; then
    nft add set $FAMILY_NAME debug WATCH_IPV6_SADDR '{ type ipv6_addr; flags interval; auto-merge ; }'
  fi
  nft flush set $FAMILY_NAME debug WATCH_IPV6_SADDR
  for ip in ${DEBUG_WATCH_IPV6_SADDR[@]}; do
    nft add element $FAMILY_NAME debug WATCH_IPV6_SADDR "{ $ip }"
  done

  nft list set $FAMILY_NAME debug WATCH_TPROXY_IPV6_ADDR >/dev/null 2>&1
  if [[ $? -ne 0 ]]; then
    nft add set $FAMILY_NAME debug WATCH_TPROXY_IPV6_ADDR '{ type ipv6_addr; flags interval; auto-merge ; }'
  fi
  nft flush set $FAMILY_NAME debug WATCH_TPROXY_IPV6_ADDR
  for ip in ${DEBUG_TPROXY_IPV6_ADDR[@]}; do
    nft add element $FAMILY_NAME debug WATCH_TPROXY_IPV6_ADDR "{ $ip }"
  done
}

# Setup debug chain for inet
nft list table inet debug >/dev/null 2>&1
if [[ $? -ne 0 ]]; then
  nft add table inet debug
fi
init_debug_ip_sets inet

nft list chain inet debug FORWARD >/dev/null 2>&1
if [[ $? -ne 0 ]]; then
  nft add chain inet debug FORWARD { type filter hook forward priority mangle - 99 \; }
fi
nft add rule inet debug FORWARD ip saddr @WATCH_IPV4_SADDR meta nftrace set 1
nft add rule inet debug FORWARD ip saddr @WATCH_IPV4_SADDR log prefix '"[DEBUG PACKET]: FORWARD:"' level debug flags all
nft add rule inet debug FORWARD ip6 saddr @WATCH_IPV6_SADDR meta nftrace set 1
nft add rule inet debug FORWARD ip6 saddr @WATCH_IPV6_SADDR log prefix '"[DEBUG PACKET]: FORWARD:"' level debug flags all
nft add rule inet debug FORWARD ip daddr @WATCH_IPV4_DADDR meta nftrace set 1
nft add rule inet debug FORWARD ip daddr @WATCH_IPV4_DADDR log prefix '"[DEBUG PACKET]: FORWARD:"' level debug flags all
nft add rule inet debug FORWARD ip6 daddr @WATCH_IPV6_DADDR meta nftrace set 1
nft add rule inet debug FORWARD ip6 daddr @WATCH_IPV6_DADDR log prefix '"[DEBUG PACKET]: FORWARD:"' level debug flags all

nft list chain inet debug PREROUTING >/dev/null 2>&1
if [[ $? -ne 0 ]]; then
  nft add chain inet debug PREROUTING { type filter hook prerouting priority raw + 1 \; }
fi
nft flush chain inet debug PREROUTING
nft add rule inet debug PREROUTING ip saddr @WATCH_IPV4_SADDR meta nftrace set 1
nft add rule inet debug PREROUTING ip saddr @WATCH_IPV4_SADDR log prefix '"[DEBUG PACKET]: PREROUTING:"' level debug flags all
nft add rule inet debug PREROUTING ip6 saddr @WATCH_IPV6_SADDR meta nftrace set 1
nft add rule inet debug PREROUTING ip6 saddr @WATCH_IPV6_SADDR log prefix '"[DEBUG PACKET]: PREROUTING:"' level debug flags all
nft add rule inet debug PREROUTING ip daddr @WATCH_IPV4_DADDR meta nftrace set 1
nft add rule inet debug PREROUTING ip daddr @WATCH_IPV4_DADDR log prefix '"[DEBUG PACKET]: PREROUTING:"' level debug flags all
nft add rule inet debug PREROUTING ip6 daddr @WATCH_IPV6_DADDR meta nftrace set 1
nft add rule inet debug PREROUTING ip6 daddr @WATCH_IPV6_DADDR log prefix '"[DEBUG PACKET]: PREROUTING:"' level debug flags all

nft list table ip debug >/dev/null 2>&1
if [[ $? -ne 0 ]]; then
  nft add table ip debug
fi
init_debug_ip_sets ip
nft list chain ip debug PREROUTING >/dev/null 2>&1
if [[ $? -ne 0 ]]; then
  nft add chain ip debug PREROUTING { type filter hook prerouting priority filter + 1 \; }
fi
nft flush chain ip debug PREROUTING

nft add rule ip debug PREROUTING ip daddr @WATCH_TPROXY_IPV4_ADDR meta nftrace set 1
nft add rule ip debug PREROUTING ip daddr @WATCH_TPROXY_IPV4_ADDR log prefix '"[DEBUG PACKET]: PREROUTING:"' level debug flags all
nft add rule ip debug PREROUTING mark and 0x70 == 0x70 return
nft add rule ip debug PREROUTING ip daddr @WATCH_TPROXY_IPV4_ADDR meta l4proto "{udp, tcp}" tproxy to :$DEBUG_TPROXY_PORT meta mark set mark and 0xffffff80 xor 0x7c accept

nft list table ip6 debug >/dev/null 2>&1
if [[ $? -ne 0 ]]; then
  nft add table ip6 debug
fi
init_debug_ip_sets ip6
nft list chain ip6 debug PREROUTING >/dev/null 2>&1
if [[ $? -ne 0 ]]; then
  nft add chain ip6 debug PREROUTING { type filter hook prerouting priority filter + 1 \; }
fi
nft flush chain ip6 debug PREROUTING

nft add rule ip6 debug PREROUTING ip6 daddr @WATCH_TPROXY_IPV6_ADDR meta nftrace set 1
nft add rule ip6 debug PREROUTING ip6 daddr @WATCH_TPROXY_IPV6_ADDR log prefix '"[DEBUG PACKET]: PREROUTING:"' level debug flags all

nft add rule ip6 debug PREROUTING mark and 0x70 == 0x70 return
nft add rule ip6 debug PREROUTING ip6 daddr @WATCH_TPROXY_IPV6_ADDR meta l4proto "{udp, tcp}" tproxy to :$DEBUG_TPROXY_PORT meta mark set mark and 0xffffff80 xor 0x7c accept

nft list chain inet debug OUTPUT >/dev/null 2>&1
if [[ $? -ne 0 ]]; then
  nft add chain inet debug OUTPUT { type filter hook output priority filter - 99 \; }
fi
nft flush chain inet debug OUTPUT
nft add rule inet debug OUTPUT ip saddr @WATCH_IPV4_SADDR meta nftrace set 1
nft add rule inet debug OUTPUT ip saddr @WATCH_IPV4_SADDR log prefix '"[DEBUG PACKET]: OUTPUT:"' level debug flags all
nft add rule inet debug OUTPUT ip6 saddr @WATCH_IPV6_SADDR meta nftrace set 1
nft add rule inet debug OUTPUT ip6 saddr @WATCH_IPV6_SADDR log prefix '"[DEBUG PACKET]: OUTPUT:"' level debug flags all
nft add rule inet debug OUTPUT ip daddr @WATCH_IPV4_DADDR meta nftrace set 1
nft add rule inet debug OUTPUT ip daddr @WATCH_IPV4_DADDR log prefix '"[DEBUG PACKET]: OUTPUT:"' level debug flags all
nft add rule inet debug OUTPUT ip6 daddr @WATCH_IPV6_DADDR meta nftrace set 1
nft add rule inet debug OUTPUT ip6 daddr @WATCH_IPV6_DADDR log prefix '"[DEBUG PACKET]: OUTPUT:"' level debug flags all

nft list chain ip debug OUTPUT >/dev/null 2>&1
if [[ $? -ne 0 ]]; then
  nft add chain ip debug OUTPUT { type route hook output priority filter + 1 \; }
fi
nft flush chain ip debug OUTPUT

nft add rule ip debug OUTPUT ip daddr @WATCH_TPROXY_IPV4_ADDR meta nftrace set 1
nft add rule ip debug OUTPUT ip daddr @WATCH_TPROXY_IPV4_ADDR log prefix '"[DEBUG PACKET]: OUTPUT:"' level debug flags all
nft add rule ip debug OUTPUT mark and 0x70 == 0x70 return
nft add rule ip debug OUTPUT ip daddr @WATCH_TPROXY_IPV4_ADDR mark and 0x1f != 0x1e meta l4proto {tcp, udp} mark set mark and 0xffffffe0 xor 0x1e return

nft list chain ip6 debug OUTPUT >/dev/null 2>&1
if [[ $? -ne 0 ]]; then
  nft add chain ip6 debug OUTPUT { type route hook output priority filter + 1 \; }
fi
nft flush chain ip6 debug OUTPUT

nft add rule ip6 debug OUTPUT ip6 daddr @WATCH_TPROXY_IPV6_ADDR meta nftrace set 1
nft add rule ip6 debug OUTPUT ip6 daddr @WATCH_TPROXY_IPV6_ADDR log prefix '"[DEBUG PACKET]: OUTPUT:"' level debug flags all
nft add rule ip6 debug OUTPUT mark and 0x70 == 0x70 return
nft add rule ip6 debug OUTPUT ip6 daddr @WATCH_TPROXY_IPV6_ADDR mark and 0x1f != 0x1e meta l4proto {tcp, udp} mark set mark and 0xffffffe0 xor 0x1e return

# Setup debug chain for bridge
nft list table bridge debug >/dev/null 2>&1
if [[ $? -ne 0 ]]; then
  nft add table bridge debug
fi
init_debug_ip_sets bridge

nft list chain bridge debug PREROUTING >/dev/null 2>&1
if [[ $? -ne 0 ]]; then
  nft add chain bridge debug PREROUTING '{ type filter hook prerouting priority -299 ; }'
fi
init_debug_ip_sets bridge

nft flush chain bridge debug PREROUTING
nft add rule bridge debug PREROUTING ip saddr @WATCH_IPV4_SADDR meta nftrace set 1
nft add rule bridge debug PREROUTING ip saddr @WATCH_IPV4_SADDR log prefix '"[DEBUG PACKET]: TCP>>PREROUTING:"' level debug flags all
nft add rule bridge debug PREROUTING ip6 saddr @WATCH_IPV6_SADDR meta nftrace set 1
nft add rule bridge debug PREROUTING ip6 saddr @WATCH_IPV6_SADDR log prefix '"[DEBUG PACKET]: TCP>>PREROUTING:"' level debug flags all
nft add rule bridge debug PREROUTING ip daddr @WATCH_IPV4_DADDR meta nftrace set 1
nft add rule bridge debug PREROUTING ip daddr @WATCH_IPV4_DADDR log prefix '"[DEBUG PACKET]: TCP>>PREROUTING:"' level debug flags all
nft add rule bridge debug PREROUTING ip6 daddr @WATCH_IPV6_DADDR meta nftrace set 1
nft add rule bridge debug PREROUTING ip6 daddr @WATCH_IPV6_DADDR log prefix '"[DEBUG PACKET]: TCP>>PREROUTING:"' level debug flags all

nft add rule bridge debug PREROUTING ip daddr @WATCH_TPROXY_IPV4_ADDR meta nftrace set 1
nft add rule bridge debug PREROUTING ip daddr @WATCH_TPROXY_IPV4_ADDR log prefix '"[DEBUG PACKET]: TCP>>PREROUTING:"' level debug flags all
nft add rule bridge debug PREROUTING ip daddr @WATCH_TPROXY_IPV4_ADDR meta pkttype set unicast
nft add rule bridge debug PREROUTING ip6 daddr @WATCH_TPROXY_IPV6_ADDR meta nftrace set 1
nft add rule bridge debug PREROUTING ip6 daddr @WATCH_TPROXY_IPV6_ADDR log prefix '"[DEBUG PACKET]: TCP>>PREROUTING:"' level debug flags all
nft add rule bridge debug PREROUTING ip6 daddr @WATCH_TPROXY_IPV6_ADDR meta pkttype set unicast

# Debug tproxy
if [[ ${#DEBUG_TPROXY_IPV4_ADDR[@]} -eq 0 ]] && [[ ${#DEBUG_TPROXY_IPV6_ADDR[@]} -eq 0 ]]; then
  exit 0
fi

if [[ $(ip -4 route list 0.0.0.0/0 dev lo table $DEBUG_TPROXY_TABLE_ID | wc -l) -eq 0 ]]; then
  ip -4 route add local 0.0.0.0/0 dev lo table $DEBUG_TPROXY_TABLE_ID
fi

DEBUG_FWMARK_LOOPUP_TABLE=$(ip -4 rule show fwmark 0x1e/0x1f lookup $DEBUG_TPROXY_TABLE_ID | awk 'END {print NF}')
while [[ 0 -ne $DEBUG_FWMARK_LOOPUP_TABLE ]]; do
  ip -4 rule delete fwmark 0x1e/0x1f lookup $DEBUG_TPROXY_TABLE_ID
  DEBUG_FWMARK_LOOPUP_TABLE=$(ip -4 rule show fwmark 0x1e/0x1f lookup $DEBUG_TPROXY_TABLE_ID | awk 'END {print NF}')
done
SETUP_FWMARK_RULE_RETRY_TIMES=0
ip -4 rule add fwmark 0x1e/0x1f priority $DEBUG_FWMARK_RULE_PRIORITY lookup $DEBUG_TPROXY_TABLE_ID
while [[ $? -ne 0 ]] && [[ $SETUP_FWMARK_RULE_RETRY_TIMES -lt 1000 ]]; do
  let SETUP_FWMARK_RULE_RETRY_TIMES=$SETUP_FWMARK_RULE_RETRY_TIMES+1
  let DEBUG_FWMARK_RULE_PRIORITY=$DEBUG_FWMARK_RULE_PRIORITY-1
  ip -4 rule add fwmark 0x1e/0x1f priority $DEBUG_FWMARK_RULE_PRIORITY lookup $DEBUG_TPROXY_TABLE_ID
done

if [[ $TPROXY_SETUP_WITHOUT_IPV6 -eq 0 ]]; then
  if [[ $(ip -6 route list ::/0 dev lo table $DEBUG_TPROXY_TABLE_ID | wc -l) -eq 0 ]]; then
    ip -6 route add local ::/0 dev lo table $DEBUG_TPROXY_TABLE_ID
  fi
  DEBUG_FWMARK_LOOPUP_TABLE=$(ip -6 rule show fwmark 0x1e/0x1f lookup $DEBUG_TPROXY_TABLE_ID | awk 'END {print NF}')
  while [[ 0 -ne $DEBUG_FWMARK_LOOPUP_TABLE ]]; do
    ip -6 rule delete fwmark 0x1e/0x1f lookup $DEBUG_TPROXY_TABLE_ID
    DEBUG_FWMARK_LOOPUP_TABLE=$(ip -6 rule show fwmark 0x1e/0x1f lookup $DEBUG_TPROXY_TABLE_ID | awk 'END {print NF}')
  done
  SETUP_FWMARK_RULE_RETRY_TIMES=0
  ip -6 rule add fwmark 0x1e/0x1f priority $DEBUG_FWMARK_RULE_PRIORITY lookup $DEBUG_TPROXY_TABLE_ID
  while [[ $? -ne 0 ]] && [[ $SETUP_FWMARK_RULE_RETRY_TIMES -lt 1000 ]]; do
    let SETUP_FWMARK_RULE_RETRY_TIMES=$SETUP_FWMARK_RULE_RETRY_TIMES+1
    let DEBUG_FWMARK_RULE_PRIORITY=$DEBUG_FWMARK_RULE_PRIORITY-1
    ip -6 rule add fwmark 0x1e/0x1f priority $DEBUG_FWMARK_RULE_PRIORITY lookup $DEBUG_TPROXY_TABLE_ID
  done
else
  DEBUG_FWMARK_LOOPUP_TABLE=$(ip -6 rule show fwmark 0x1e/0x1f lookup $DEBUG_TPROXY_TABLE_ID | awk 'END {print NF}')
  while [[ 0 -ne $DEBUG_FWMARK_LOOPUP_TABLE ]]; do
    ip -6 rule delete fwmark 0x1e/0x1f lookup $DEBUG_TPROXY_TABLE_ID
    DEBUG_FWMARK_LOOPUP_TABLE=$(ip -6 rule show fwmark 0x1e/0x1f lookup $DEBUG_TPROXY_TABLE_ID | awk 'END {print NF}')
  done
  ip -6 route del local ::/0 dev lo table $DEBUG_TPROXY_TABLE_ID >/dev/null 2>&1
fi
# ip route show table $DEBUG_TPROXY_TABLE_ID
