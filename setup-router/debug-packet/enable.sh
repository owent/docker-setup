#!/bin/bash

#### ========== debug ==========
#### Use nft monitor trace to see the packet trace
DEBUG_WATCH_IPV4_DADDR=()
DEBUG_WATCH_IPV4_SADDR=()

DEBUG_WATCH_IPV6_DADDR=(2402:4e00:: 2400:3200:baba::1)
DEBUG_WATCH_IPV6_SADDR=(${DEBUG_WATCH_IP6_DADDR[@]})

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
  for ip in ${DEBUG_WATCH_IPV4_DADDR[@]}; do
    nft add element $FAMILY_NAME debug WATCH_IPV4_SADDR "{ $ip }"
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
  for ip in ${DEBUG_WATCH_IPV6_DADDR[@]}; do
    nft add element $FAMILY_NAME debug WATCH_IPV6_SADDR "{ $ip }"
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
