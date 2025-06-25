#!/bin/bash

#### ========== debug ==========
#### Use nft monitor trace to see the packet trace
DEBUG_WATCH_IPV4_DADDR=()
DEBUG_WATCH_IPV4_SADDR=(${DEBUG_WATCH_IPV4_DADDR[@]})

DEBUG_WATCH_IPV6_DADDR=() #(2402:4e00:: 2400:3200:baba::1)
DEBUG_WATCH_IPV6_SADDR=() #(${DEBUG_WATCH_IP6_DADDR[@]})

DEBUG_WATCH_TCP_DPORT=()
DEBUG_WATCH_TCP_SPORT=(${DEBUG_WATCH_TCP_DPORT[@]})

DEBUG_WATCH_UDP_DPORT=()
DEBUG_WATCH_UDP_SPORT=(${DEBUG_WATCH_UDP_DPORT[@]})

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

  nft list set $FAMILY_NAME debug WATCH_TCP_DPORT >/dev/null 2>&1
  if [[ $? -ne 0 ]]; then
    nft add set $FAMILY_NAME debug WATCH_TCP_DPORT '{ type inet_service; }'
  fi
  nft flush set $FAMILY_NAME debug WATCH_TCP_DPORT
  for ip in ${DEBUG_WATCH_TCP_DPORT[@]}; do
    nft add element $FAMILY_NAME debug WATCH_TCP_DPORT "{ $ip }"
  done
  nft list set $FAMILY_NAME debug WATCH_TCP_SPORT >/dev/null 2>&1
  if [[ $? -ne 0 ]]; then
    nft add set $FAMILY_NAME debug WATCH_TCP_SPORT '{ type inet_service; }'
  fi
  nft flush set $FAMILY_NAME debug WATCH_TCP_SPORT
  for ip in ${DEBUG_WATCH_TCP_SPORT[@]}; do
    nft add element $FAMILY_NAME debug WATCH_TCP_SPORT "{ $ip }"
  done

  nft list set $FAMILY_NAME debug WATCH_UDP_DPORT >/dev/null 2>&1
  if [[ $? -ne 0 ]]; then
    nft add set $FAMILY_NAME debug WATCH_UDP_DPORT '{ type inet_service; }'
  fi
  nft flush set $FAMILY_NAME debug WATCH_UDP_DPORT
  for ip in ${DEBUG_WATCH_UDP_DPORT[@]}; do
    nft add element $FAMILY_NAME debug WATCH_UDP_DPORT "{ $ip }"
  done
  nft list set $FAMILY_NAME debug WATCH_UDP_SPORT >/dev/null 2>&1
  if [[ $? -ne 0 ]]; then
    nft add set $FAMILY_NAME debug WATCH_UDP_SPORT '{ type inet_service; }'
  fi
  nft flush set $FAMILY_NAME debug WATCH_UDP_SPORT
  for ip in ${DEBUG_WATCH_UDP_SPORT[@]}; do
    nft add element $FAMILY_NAME debug WATCH_UDP_SPORT "{ $ip }"
  done
}

function setup_debug_trace_rule_with_ports() {
  if [[ ${#DEBUG_WATCH_TCP_DPORT[@]} -gt 0 ]] || [[ ${#DEBUG_WATCH_TCP_SPORT[@]} -gt 0 ]] || [[ ${#DEBUG_WATCH_UDP_SPORT[@]} -gt 0 ]] || [[ ${#DEBUG_WATCH_UDP_DPORT[@]} -gt 0 ]]; then
    if [[ ${#DEBUG_WATCH_TCP_DPORT[@]} -gt 0 ]]; then
      "$@" tcp dport @WATCH_TCP_DPORT meta nftrace set 1
      "$@" tcp dport @WATCH_TCP_DPORT log prefix "\"[DEBUG PACKET]: $6:\"" level debug flags all
    fi
    if [[ ${#DEBUG_WATCH_TCP_SPORT[@]} -gt 0 ]]; then
      "$@" tcp sport @WATCH_TCP_SPORT meta nftrace set 1
      "$@" tcp sport @WATCH_TCP_SPORT log prefix "\"[DEBUG PACKET]: $6:\"" level debug flags all
    fi
    if [[ ${#DEBUG_WATCH_UDP_DPORT[@]} -gt 0 ]]; then
      "$@" udp dport @WATCH_UDP_DPORT meta nftrace set 1
      "$@" udp dport @WATCH_UDP_DPORT log prefix "\"[DEBUG PACKET]: $6:\"" level debug flags all
    fi
    if [[ ${#DEBUG_WATCH_UDP_SPORT[@]} -gt 0 ]]; then
      "$@" udp sport @WATCH_UDP_SPORT meta nftrace set 1
      "$@" udp sport @WATCH_UDP_SPORT log prefix "\"[DEBUG PACKET]: $6:\"" level debug flags all
    fi
  else
    "$@" meta nftrace set 1
    "$@" log prefix "\"[DEBUG PACKET]: $6:\"" level debug flags all
  fi
}

# Setup debug chain for inet
nft list table inet debug >/dev/null 2>&1
if [[ $? -ne 0 ]]; then
  nft add table inet debug
fi
init_debug_ip_sets inet

nft list chain inet debug FORWARD >/dev/null 2>&1
if [[ $? -ne 0 ]]; then
  nft add chain inet debug FORWARD { type filter hook forward priority mangle - 100 \; }
fi

setup_debug_trace_rule_with_ports nft add rule inet debug FORWARD ip saddr @WATCH_IPV4_SADDR
setup_debug_trace_rule_with_ports nft add rule inet debug FORWARD ip6 saddr @WATCH_IPV6_SADDR
setup_debug_trace_rule_with_ports nft add rule inet debug FORWARD ip daddr @WATCH_IPV4_DADDR
setup_debug_trace_rule_with_ports nft add rule inet debug FORWARD ip6 daddr @WATCH_IPV6_DADDR

nft list chain inet debug PREROUTING >/dev/null 2>&1
if [[ $? -ne 0 ]]; then
  nft add chain inet debug PREROUTING { type filter hook prerouting priority raw + 1 \; }
fi
nft flush chain inet debug PREROUTING
setup_debug_trace_rule_with_ports nft add rule inet debug PREROUTING ip saddr @WATCH_IPV4_SADDR
setup_debug_trace_rule_with_ports nft add rule inet debug PREROUTING ip6 saddr @WATCH_IPV6_SADDR
setup_debug_trace_rule_with_ports nft add rule inet debug PREROUTING ip daddr @WATCH_IPV4_DADDR
setup_debug_trace_rule_with_ports nft add rule inet debug PREROUTING ip6 daddr @WATCH_IPV6_DADDR

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

setup_debug_trace_rule_with_ports nft add rule ip debug PREROUTING ip daddr @WATCH_TPROXY_IPV4_ADDR
nft add rule ip debug PREROUTING mark and 0x70 == 0x70 return
nft add rule ip debug PREROUTING ip daddr @WATCH_TPROXY_IPV4_ADDR meta l4proto "{udp, tcp}" tproxy to :$DEBUG_TPROXY_PORT meta mark set mark and 0xffffff80 xor 0x7e accept

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

setup_debug_trace_rule_with_ports nft add rule ip6 debug PREROUTING ip6 daddr @WATCH_TPROXY_IPV6_ADDR

nft add rule ip6 debug PREROUTING mark and 0x70 == 0x70 return
nft add rule ip6 debug PREROUTING ip6 daddr @WATCH_TPROXY_IPV6_ADDR meta l4proto "{udp, tcp}" tproxy to :$DEBUG_TPROXY_PORT meta mark set mark and 0xffffff80 xor 0x7e accept

nft list chain inet debug OUTPUT >/dev/null 2>&1
if [[ $? -ne 0 ]]; then
  nft add chain inet debug OUTPUT { type filter hook output priority mangle - 100 \; }
fi
nft flush chain inet debug OUTPUT
setup_debug_trace_rule_with_ports nft add rule inet debug OUTPUT ip saddr @WATCH_IPV4_SADDR
setup_debug_trace_rule_with_ports nft add rule inet debug OUTPUT ip6 saddr @WATCH_IPV6_SADDR
setup_debug_trace_rule_with_ports nft add rule inet debug OUTPUT ip daddr @WATCH_IPV4_DADDR
setup_debug_trace_rule_with_ports nft add rule inet debug OUTPUT ip6 daddr @WATCH_IPV6_DADDR

nft list chain ip debug OUTPUT >/dev/null 2>&1
if [[ $? -ne 0 ]]; then
  nft add chain ip debug OUTPUT { type route hook output priority filter + 1 \; }
fi
nft flush chain ip debug OUTPUT

setup_debug_trace_rule_with_ports nft add rule ip debug OUTPUT ip daddr @WATCH_TPROXY_IPV4_ADDR
nft add rule ip debug OUTPUT mark and 0x70 == 0x70 return
nft add rule ip debug OUTPUT ip daddr @WATCH_TPROXY_IPV4_ADDR mark and 0x1f != 0x1e meta l4proto {tcp, udp} mark set mark and 0xffffffe0 xor 0x1e return

nft list chain ip6 debug OUTPUT >/dev/null 2>&1
if [[ $? -ne 0 ]]; then
  nft add chain ip6 debug OUTPUT { type route hook output priority filter + 1 \; }
fi
nft flush chain ip6 debug OUTPUT

setup_debug_trace_rule_with_ports nft add rule ip6 debug OUTPUT ip6 daddr @WATCH_TPROXY_IPV6_ADDR
nft add rule ip6 debug OUTPUT mark and 0x70 == 0x70 return
nft add rule ip6 debug OUTPUT ip6 daddr @WATCH_TPROXY_IPV6_ADDR mark and 0x1f != 0x1e meta l4proto {tcp, udp} mark set mark and 0xffffffe0 xor 0x1e return

nft list chain inet debug INPUT >/dev/null 2>&1
if [[ $? -ne 0 ]]; then
  nft add chain inet debug INPUT { type filter hook input priority mangle - 100 \; }
fi
nft flush chain inet debug INPUT
setup_debug_trace_rule_with_ports nft add rule inet debug INPUT ip saddr @WATCH_IPV4_SADDR
setup_debug_trace_rule_with_ports nft add rule inet debug INPUT ip6 saddr @WATCH_IPV6_SADDR
setup_debug_trace_rule_with_ports nft add rule inet debug INPUT ip daddr @WATCH_IPV4_DADDR
setup_debug_trace_rule_with_ports nft add rule inet debug INPUT ip6 daddr @WATCH_IPV6_DADDR

nft list chain ip debug INPUT >/dev/null 2>&1
if [[ $? -ne 0 ]]; then
  nft add chain ip debug INPUT { type nat hook input priority mangle - 1 \; }
fi
nft flush chain ip debug INPUT

setup_debug_trace_rule_with_ports nft add rule ip debug INPUT ip daddr @WATCH_TPROXY_IPV4_ADDR
nft add rule ip debug INPUT mark and 0x70 == 0x70 return
nft add rule ip debug INPUT ip daddr @WATCH_TPROXY_IPV4_ADDR mark and 0x1f != 0x1e meta l4proto {tcp, udp} mark set mark and 0xffffffe0 xor 0x1e return

nft list chain ip6 debug INPUT >/dev/null 2>&1
if [[ $? -ne 0 ]]; then
  nft add chain ip6 debug INPUT { type nat hook output priority mangle - 1 \; }
fi
nft flush chain ip6 debug INPUT

setup_debug_trace_rule_with_ports nft add rule ip6 debug INPUT ip6 daddr @WATCH_TPROXY_IPV6_ADDR
nft add rule ip6 debug INPUT mark and 0x70 == 0x70 return
nft add rule ip6 debug INPUT ip6 daddr @WATCH_TPROXY_IPV6_ADDR mark and 0x1f != 0x1e meta l4proto {tcp, udp} mark set mark and 0xffffffe0 xor 0x1e return

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
setup_debug_trace_rule_with_ports nft add rule bridge debug PREROUTING ip saddr @WATCH_IPV4_SADDR
setup_debug_trace_rule_with_ports nft add rule bridge debug PREROUTING ip6 saddr @WATCH_IPV6_SADDR
setup_debug_trace_rule_with_ports nft add rule bridge debug PREROUTING ip daddr @WATCH_IPV4_DADDR
setup_debug_trace_rule_with_ports nft add rule bridge debug PREROUTING ip6 daddr @WATCH_IPV6_DADDR

setup_debug_trace_rule_with_ports nft add rule bridge debug PREROUTING ip daddr @WATCH_TPROXY_IPV4_ADDR
nft add rule bridge debug PREROUTING ip daddr @WATCH_TPROXY_IPV4_ADDR meta pkttype set unicast
setup_debug_trace_rule_with_ports nft add rule bridge debug PREROUTING ip6 daddr @WATCH_TPROXY_IPV6_ADDR
nft add rule bridge debug PREROUTING ip6 daddr @WATCH_TPROXY_IPV6_ADDR meta pkttype set unicast

# Debug tproxy
if [[ ${#DEBUG_TPROXY_IPV4_ADDR[@]} -eq 0 ]] && [[ ${#DEBUG_TPROXY_IPV6_ADDR[@]} -eq 0 ]]; then
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
