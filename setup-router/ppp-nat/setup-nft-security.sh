#!/bin/bash

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
source "$(dirname "$SCRIPT_DIR")/configure-router.sh"

nft list table inet security_firewall >/dev/null 2>&1
if [[ $? -eq 0 ]]; then
  FLUSH_CHAINS=(PREROUTING INPUT OUTPUT FORWARD)
  for TEST_CHAIN_NAME in ${FLUSH_CHAINS[@]}; do
    nft list chain inet security_firewall $TEST_CHAIN_NAME >/dev/null 2>&1
    if [[ $? -eq 0 ]]; then
      echo "Remove old chain: inet security_firewall $TEST_CHAIN_NAME"
      nft delete chain inet security_firewall $TEST_CHAIN_NAME
    fi
  done
else
  nft add table inet security_firewall
fi

nft list set inet security_firewall LOCAL_IPV4 >/dev/null 2>&1
if [[ $? -ne 0 ]]; then
  nft add set inet security_firewall LOCAL_IPV4 '{ type ipv4_addr; flags interval; auto-merge ; }'
  nft add element inet security_firewall LOCAL_IPV4 '{0.0.0.0/8, 10.0.0.0/8, 127.0.0.0/8, 169.254.0.0/16, 172.16.0.0/12, 192.0.0.0/24, 192.168.0.0/16, 224.0.0.0/4, 240.0.0.0/4}'
fi

nft list set inet security_firewall LOCAL_IPV6 >/dev/null 2>&1
if [[ $? -ne 0 ]]; then
  nft add set inet security_firewall LOCAL_IPV6 '{ type ipv6_addr; flags interval; auto-merge ; }'
  nft add element inet security_firewall LOCAL_IPV6 '{::1/128, ::/128, ::ffff:0:0/96, 64:ff9b::/96, 100::/64, fc00::/7, fe80::/10, ff00::/8}'
fi

# Ports
nft list set inet security_firewall LOCAL_SERVICE_PRIVATE_PORT_UDP >/dev/null 2>&1
if [[ $? -ne 0 ]]; then
  nft add set inet security_firewall LOCAL_SERVICE_PRIVATE_PORT_UDP '{ type inet_service; flags interval; auto-merge; }'
  nft add element inet security_firewall LOCAL_SERVICE_PRIVATE_PORT_UDP "{$ROUTER_INTERNAL_SERVICE_PRIVATE_PORT_UDP}"
fi
nft list set inet security_firewall LOCAL_SERVICE_PRIVATE_PORT_TCP >/dev/null 2>&1
if [[ $? -ne 0 ]]; then
  nft add set inet security_firewall LOCAL_SERVICE_PRIVATE_PORT_TCP '{ type inet_service; flags interval; auto-merge; }'
  nft add element inet security_firewall LOCAL_SERVICE_PRIVATE_PORT_TCP "{$ROUTER_INTERNAL_SERVICE_PRIVATE_PORT_TCP}"
fi
nft list set inet security_firewall LOCAL_SERVICE_PUBLIC_PORT_UDP >/dev/null 2>&1
if [[ $? -ne 0 ]]; then
  nft add set inet security_firewall LOCAL_SERVICE_PUBLIC_PORT_UDP '{ type inet_service; flags interval; auto-merge; }'
  nft add element inet security_firewall LOCAL_SERVICE_PUBLIC_PORT_UDP "{$ROUTER_INTERNAL_SERVICE_PUBLIC_PORT_UDP}"

  if [[ ! -z "$ROUTER_INTERNAL_DIRECTLY_VISIT_UDP_DPORT" ]]; then
    nft add element inet security_firewall LOCAL_SERVICE_PUBLIC_PORT_UDP "{$ROUTER_INTERNAL_DIRECTLY_VISIT_UDP_DPORT}"
  fi
fi
nft list set inet security_firewall LOCAL_SERVICE_PUBLIC_PORT_TCP >/dev/null 2>&1
if [[ $? -ne 0 ]]; then
  nft add set inet security_firewall LOCAL_SERVICE_PUBLIC_PORT_TCP '{ type inet_service; flags interval; auto-merge; }'
  nft add element inet security_firewall LOCAL_SERVICE_PUBLIC_PORT_TCP "{$ROUTER_INTERNAL_SERVICE_PUBLIC_PORT_TCP}"
fi

nft add chain inet security_firewall PREROUTING '{ type filter hook prerouting priority filter + 10; policy accept; }'
nft add rule inet security_firewall PREROUTING icmp type destination-unreachable icmp code frag-needed accept
nft add rule inet security_firewall PREROUTING icmpv6 type '{ nd-router-advert, nd-neighbor-solicit, packet-too-big }' accept
nft add rule inet security_firewall PREROUTING meta nfproto ipv6 meta iifkind != '{ "tun" }' fib saddr . iif oif missing drop

nft add chain inet security_firewall INPUT '{ type filter hook input priority filter + 10; policy accept; }'
nft add rule inet security_firewall INPUT ct state { established, related } accept
nft add rule inet security_firewall INPUT ct status dnat accept
nft add rule inet security_firewall INPUT iifname "$ROUTER_LOCAL_LAN_INTERFACE" accept
# Internal services -- begin
nft add rule inet security_firewall INPUT ip saddr @LOCAL_IPV4 tcp dport "@LOCAL_SERVICE_PRIVATE_PORT_TCP" ct state { new, untracked } accept
nft add rule inet security_firewall INPUT ip saddr @LOCAL_IPV4 udp dport "@LOCAL_SERVICE_PRIVATE_PORT_UDP" ct state { new, untracked } accept
nft add rule inet security_firewall INPUT ip6 saddr @LOCAL_IPV6 tcp dport "@LOCAL_SERVICE_PRIVATE_PORT_TCP" ct state { new, untracked } accept
nft add rule inet security_firewall INPUT ip6 saddr @LOCAL_IPV6 udp dport "@LOCAL_SERVICE_PRIVATE_PORT_UDP" ct state { new, untracked } accept
nft add rule inet security_firewall INPUT ip6 daddr fe80::/64 udp dport 546 ct state { new, untracked } accept
nft add rule inet security_firewall INPUT tcp dport "@LOCAL_SERVICE_PUBLIC_PORT_TCP" ct state { new, untracked } accept
nft add rule inet security_firewall INPUT udp dport "@LOCAL_SERVICE_PUBLIC_PORT_UDP" ct state { new, untracked } accept
# Internal services -- end
nft add rule inet security_firewall INPUT meta l4proto { icmp, ipv6-icmp } accept
nft add rule inet security_firewall INPUT ct state { invalid } drop
nft add rule inet security_firewall INPUT reject with icmpx type admin-prohibited

nft add chain inet security_firewall OUTPUT '{ type filter hook output priority filter + 10; policy accept; }'
nft add rule inet security_firewall OUTPUT oifname "lo" accept
nft add rule inet security_firewall OUTPUT ip6 daddr { ::/96, ::ffff:0.0.0.0/96, 2002::/24, 2002:a00::/24, 2002:7f00::/24, 2002:a9fe::/32, 2002:ac10::/28, 2002:c0a8::/32, 2002:e000::/19 } reject with icmpv6 type addr-unreachable

nft add chain inet security_firewall FORWARD '{ type filter hook forward priority filter + 10; policy accept; }'
nft add rule inet security_firewall FORWARD ct state { established, related } accept
nft add rule inet security_firewall FORWARD ct status dnat accept
nft add rule inet security_firewall FORWARD iifname "$ROUTER_LOCAL_LAN_INTERFACE" accept
nft add rule inet security_firewall FORWARD ip6 daddr { ::/96, ::ffff:0.0.0.0/96, 2002::/24, 2002:a00::/24, 2002:7f00::/24, 2002:a9fe::/32, 2002:ac10::/28, 2002:c0a8::/32, 2002:e000::/19 } reject with icmpv6 type addr-unreachable
#
nft add rule inet security_firewall FORWARD meta l4proto { icmp, ipv6-icmp } accept
nft add rule inet security_firewall FORWARD ct state { new, untracked } accept
#
nft add rule inet security_firewall FORWARD ct state { invalid } drop
nft add rule inet security_firewall FORWARD reject with icmpx type admin-prohibited
