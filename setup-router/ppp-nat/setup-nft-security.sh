#!/bin/bash

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
source "$(dirname "$SCRIPT_DIR")/configure-router.sh"

PUBLIC_UDP_PORTS="$ROUTER_INTERNAL_SERVICE_PUBLIC_PORT_UDP"
if [[ -n "$ROUTER_INTERNAL_DIRECTLY_VISIT_UDP_DPORT" ]]; then
  PUBLIC_UDP_PORTS+=",$ROUTER_INTERNAL_DIRECTLY_VISIT_UDP_DPORT"
fi

# Inspect the table once. Keep LOCAL_IPV4/LOCAL_IPV6 if another script already
# populated them with a more specific range.
EXISTING_TABLE="$(nft list table inet security_firewall 2>/dev/null)"
RESET_OBJECTS=
for CHAIN_NAME in PREROUTING INPUT OUTPUT FORWARD; do
  if [[ "$EXISTING_TABLE" == *"chain $CHAIN_NAME {"* ]]; then
    RESET_OBJECTS+="flush chain inet security_firewall $CHAIN_NAME"$'\n'
    RESET_OBJECTS+="delete chain inet security_firewall $CHAIN_NAME"$'\n'
  fi
done
for SET_NAME in LOCAL_SERVICE_PRIVATE_PORT_UDP LOCAL_SERVICE_PRIVATE_PORT_TCP LOCAL_SERVICE_PUBLIC_PORT_UDP LOCAL_SERVICE_PUBLIC_PORT_TCP BLOCKED_IPV4 BLOCKED_IPV6; do
  if [[ "$EXISTING_TABLE" == *"set $SET_NAME {"* ]]; then
    RESET_OBJECTS+="delete set inet security_firewall $SET_NAME"$'\n'
  fi
done

LOCAL_IPV4_DEFINITION=
if [[ "$EXISTING_TABLE" != *"set LOCAL_IPV4 {"* ]]; then
  LOCAL_IPV4_DEFINITION='
  set LOCAL_IPV4 {
    type ipv4_addr
    flags interval
    auto-merge
    elements = { 0.0.0.0/8, 10.0.0.0/8, 127.0.0.0/8, 169.254.0.0/16, 172.16.0.0/12, 192.0.0.0/24, 192.168.0.0/16, 224.0.0.0/4, 240.0.0.0/4 }
  }'
fi

LOCAL_IPV6_DEFINITION=
if [[ "$EXISTING_TABLE" != *"set LOCAL_IPV6 {"* ]]; then
  LOCAL_IPV6_DEFINITION='
  set LOCAL_IPV6 {
    type ipv6_addr
    flags interval
    auto-merge
    elements = { ::1/128, ::/128, ::ffff:0:0/96, 64:ff9b::/96, 100::/64, fc00::/7, fe80::/10, ff00::/8 }
  }'
fi

ROUTER_INTERNAL_SERVICE_BLOCKED_IPV4=
if ((${#ROUTER_SECURITY_BLOCKED_IPV4[@]})); then
  ROUTER_INTERNAL_SERVICE_BLOCKED_IPV4="elements = { $(IFS=,; printf '%s' "${ROUTER_SECURITY_BLOCKED_IPV4[*]}") }"
fi
ROUTER_INTERNAL_SERVICE_BLOCKED_IPV6=
if ((${#ROUTER_SECURITY_BLOCKED_IPV6[@]})); then
  ROUTER_INTERNAL_SERVICE_BLOCKED_IPV6="elements = { $(IFS=,; printf '%s' "${ROUTER_SECURITY_BLOCKED_IPV6[*]}") }"
fi

nft -f - <<EOF
add table inet security_firewall
$RESET_OBJECTS
table inet security_firewall {
$LOCAL_IPV4_DEFINITION
$LOCAL_IPV6_DEFINITION

  set LOCAL_SERVICE_PRIVATE_PORT_UDP {
    type inet_service
    flags interval
    auto-merge
    elements = { $ROUTER_INTERNAL_SERVICE_PRIVATE_PORT_UDP }
  }

  set LOCAL_SERVICE_PRIVATE_PORT_TCP {
    type inet_service
    flags interval
    auto-merge
    elements = { $ROUTER_INTERNAL_SERVICE_PRIVATE_PORT_TCP }
  }

  set LOCAL_SERVICE_PUBLIC_PORT_UDP {
    type inet_service
    flags interval
    auto-merge
    elements = { $PUBLIC_UDP_PORTS }
  }

  set LOCAL_SERVICE_PUBLIC_PORT_TCP {
    type inet_service
    flags interval
    auto-merge
    elements = { $ROUTER_INTERNAL_SERVICE_PUBLIC_PORT_TCP }
  }

  set BLOCKED_IPV4 {
    type ipv4_addr
    flags interval
    auto-merge
    $ROUTER_INTERNAL_SERVICE_BLOCKED_IPV4
  }

  set BLOCKED_IPV6 {
    type ipv6_addr
    flags interval
    auto-merge
    $ROUTER_INTERNAL_SERVICE_BLOCKED_IPV6
  }

  chain PREROUTING {
    type filter hook prerouting priority filter + 10; policy accept;
    ip saddr @BLOCKED_IPV4 drop
    ip6 saddr @BLOCKED_IPV6 drop
    icmp type destination-unreachable icmp code frag-needed accept
    icmpv6 type { nd-router-advert, nd-neighbor-solicit, packet-too-big, nd-neighbor-advert } accept
    meta nfproto ipv6 meta iifkind != { "tun" } fib saddr . iif oif missing drop
  }

  chain INPUT {
    type filter hook input priority filter + 10; policy accept;
    ct state { established, related } accept
    ct status dnat accept
    iifname $ROUTER_LOCAL_LAN_INTERFACE accept
    # Internal services -- begin
    ip saddr @LOCAL_IPV4 tcp dport @LOCAL_SERVICE_PRIVATE_PORT_TCP ct state { new, untracked } accept
    ip saddr @LOCAL_IPV4 udp dport @LOCAL_SERVICE_PRIVATE_PORT_UDP ct state { new, untracked } accept
    ip6 saddr @LOCAL_IPV6 tcp dport @LOCAL_SERVICE_PRIVATE_PORT_TCP ct state { new, untracked } accept
    ip6 saddr @LOCAL_IPV6 udp dport @LOCAL_SERVICE_PRIVATE_PORT_UDP ct state { new, untracked } accept
    ip6 daddr fe80::/64 udp dport 546 ct state { new, untracked } accept
    tcp dport @LOCAL_SERVICE_PUBLIC_PORT_TCP ct state { new, untracked } accept
    udp dport @LOCAL_SERVICE_PUBLIC_PORT_UDP ct state { new, untracked } accept
    # Internal services -- end
    meta l4proto { icmp, ipv6-icmp } accept
    ct state { invalid } drop
    reject with icmpx type admin-prohibited
  }

  chain OUTPUT {
    type filter hook output priority filter + 10; policy accept;
    oifname "lo" accept
    icmpv6 type { packet-too-big, nd-router-solicit, nd-router-advert, nd-neighbor-solicit, nd-neighbor-advert, nd-redirect } accept
    ip6 daddr { ::/96, ::ffff:0.0.0.0/96, 2002::/24, 2002:a00::/24, 2002:7f00::/24, 2002:a9fe::/32, 2002:ac10::/28, 2002:c0a8::/32, 2002:e000::/19 } reject with icmpv6 type addr-unreachable
  }

  chain FORWARD {
    type filter hook forward priority filter + 10; policy accept;
    ct state { established, related } accept
    ct status dnat accept
    iifname $ROUTER_LOCAL_LAN_INTERFACE accept
    ip6 daddr { ::/96, ::ffff:0.0.0.0/96, 2002::/24, 2002:a00::/24, 2002:7f00::/24, 2002:a9fe::/32, 2002:ac10::/28, 2002:c0a8::/32, 2002:e000::/19 } reject with icmpv6 type addr-unreachable
    meta l4proto { icmp, ipv6-icmp } accept
    ct state { new, untracked } accept
    ct state { invalid } drop
    reject with icmpx type admin-prohibited
  }
}
EOF
