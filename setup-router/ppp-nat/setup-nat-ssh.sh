#!/bin/bash

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
source "$(dirname "$SCRIPT_DIR")/configure-router.sh"

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

if [[ "x" == "x$SETUP_WITH_DEBUG_LOG" ]]; then
  SETUP_WITH_DEBUG_LOG=0
fi

# Recommand to use NDP instead of NAT6
# NAT_SETUP_SKIP_IPV6=1

## NAT
# just like iptables -t nat
nft list table ip nat >/dev/null 2>&1
if [[ $? -ne 0 ]]; then
  nft add table ip nat
fi

nft list set ip nat LOCAL_IPV4 >/dev/null 2>&1
if [[ $? -ne 0 ]]; then
  nft add set ip nat LOCAL_IPV4 '{ type ipv4_addr; flags interval; auto-merge ; }'
  nft add element ip nat LOCAL_IPV4 {127.0.0.1/32, 169.254.0.0/16, 192.168.0.0/16, 172.16.0.0/12, 10.0.0.0/8}
fi
nft list set ip nat DEFAULT_ROUTE_IPV4 >/dev/null 2>&1
if [[ $? -ne 0 ]]; then
  nft add set ip nat DEFAULT_ROUTE_IPV4 '{ type ipv4_addr; flags interval; auto-merge ; }'
fi

nft list table ip6 nat >/dev/null 2>&1
if [[ $? -ne 0 ]]; then
  if [[ $NAT_SETUP_SKIP_IPV6 -eq 0 ]]; then
    nft add table ip6 nat
  fi
else
  if [[ $NAT_SETUP_SKIP_IPV6 -ne 0 ]]; then
    nft delete table ip6 nat
  fi
fi

if [[ $NAT_SETUP_SKIP_IPV6 -eq 0 ]]; then
  nft list set ip6 nat LOCAL_IPV6 >/dev/null 2>&1
  if [[ $? -ne 0 ]]; then
    nft add set ip6 nat LOCAL_IPV6 '{ type ipv6_addr; flags interval; auto-merge ; }'
    nft add element ip6 nat LOCAL_IPV6 {::1/128, fc00::/7, fe80::/10}
  fi
  nft list set ip6 nat DEFAULT_ROUTE_IPV6 >/dev/null 2>&1
  if [[ $? -ne 0 ]]; then
    nft add set ip6 nat DEFAULT_ROUTE_IPV6 '{ type ipv6_addr; flags interval; auto-merge ; }'
  fi
fi

nft list table inet nat >/dev/null 2>&1
if [[ $? -ne 0 ]]; then
  nft add table inet nat
fi

#### ========== debug ==========
if [[ $SETUP_WITH_DEBUG_LOG -ne 0 ]]; then
  nft list table inet debug >/dev/null 2>&1
  if [[ $? -ne 0 ]]; then
    nft add table inet debug
  fi
  nft list chain inet debug FORWARD >/dev/null 2>&1
  if [[ $? -ne 0 ]]; then
    nft add chain inet debug FORWARD { type filter hook forward priority filter - 1 \; }
  fi
  nft list set inet debug WATCH >/dev/null 2>&1
  if [[ $? -ne 0 ]]; then
    nft add set inet debug WATCH { type ipv4_addr\; }
  fi
  nft flush set inet debug WATCH
  nft add element inet debug WATCH { 103.235.46.39, 180.101.49.11, 180.101.49.12 }
  nft flush chain inet debug FORWARD
  nft add rule inet debug FORWARD mark and 0xf == 0xe meta l4proto tcp meta nftrace set 1
  nft add rule inet debug FORWARD tcp dport 3371 meta nftrace set 1
  nft add rule inet debug FORWARD ip saddr @WATCH meta nftrace set 1
  nft add rule inet debug FORWARD ip saddr @WATCH log prefix '">>>TCP>>FORWARD:"' level debug flags all
  nft add rule inet debug FORWARD ip daddr @WATCH meta nftrace set 1
  nft add rule inet debug FORWARD ip daddr @WATCH log prefix '"<<<TCP<<FORWARD:"' level debug flags all
  nft add rule inet debug FORWARD ip daddr 172.23.111.179 meta l4proto icmp meta nftrace set 1
  nft add rule inet debug FORWARD ip daddr 172.23.111.179 meta l4proto icmp log prefix '"<<<ICMP:"' level debug flags all
  nft list chain inet debug PREROUTING >/dev/null 2>&1
  if [[ $? -ne 0 ]]; then
    nft add chain inet debug PREROUTING { type filter hook prerouting priority filter - 1 \; }
  fi
  nft flush chain inet debug PREROUTING
  nft add rule inet debug PREROUTING mark and 0xf == 0xe meta l4proto tcp meta nftrace set 1
  nft add rule inet debug PREROUTING tcp dport 3371 meta nftrace set 1
  nft add rule inet debug PREROUTING ip saddr @WATCH meta nftrace set 1
  nft add rule inet debug PREROUTING ip saddr @WATCH log prefix '">>>TCP>>PRERO:"' level debug flags all
  nft add rule inet debug PREROUTING ip daddr @WATCH meta nftrace set 1
  nft add rule inet debug PREROUTING ip daddr @WATCH log prefix '"<<<TCP<<PRERO:"' level debug flags all
  nft add rule inet debug PREROUTING ip daddr 172.23.111.179 meta l4proto icmp meta nftrace set 1
  nft add rule inet debug PREROUTING ip daddr 172.23.111.179 meta l4proto icmp log prefix '"<<<ICMP:"' level debug flags all
  nft list chain inet debug OUTPUT >/dev/null 2>&1
  if [[ $? -ne 0 ]]; then
    nft add chain inet debug OUTPUT { type filter hook output priority filter - 1 \; }
  fi
  nft flush chain inet debug OUTPUT
  nft add rule inet debug OUTPUT mark and 0xf == 0xe meta l4proto tcp meta nftrace set 1
  nft add rule inet debug OUTPUT tcp dport 3371 meta nftrace set 1
  nft add rule inet debug OUTPUT ip saddr @WATCH meta nftrace set 1
  nft add rule inet debug OUTPUT ip saddr @WATCH log prefix '">>>TCP>>OUTPUT:"' level debug flags all
  nft add rule inet debug OUTPUT ip daddr @WATCH meta nftrace set 1
  nft add rule inet debug OUTPUT ip daddr @WATCH log prefix '"<<<TCP<<OUTPUT:"' level debug flags all
  nft add rule inet debug OUTPUT ip daddr 172.23.111.179 meta l4proto icmp meta nftrace set 1
  nft add rule inet debug OUTPUT ip daddr 172.23.111.179 meta l4proto icmp log prefix '"<<<ICMP:"' level debug flags all
else
  nft list table inet debug >/dev/null 2>&1
  if [[ $? -eq 0 ]]; then
    nft delete table inet debug
  fi
fi

### Setup - ipv4&ipv6
nft list chain inet nat FORWARD >/dev/null 2>&1
if [[ $? -ne 0 ]]; then
  nft add chain inet nat FORWARD { type filter hook forward priority filter \; }
fi
nft flush chain inet nat FORWARD
# @see https://wiki.archlinux.org/index.php/Ppp#Masquerading_seems_to_be_working_fine_but_some_sites_do_not_work
# @see https://www.mankier.com/8/nft#Statements-Extension_Header_Statement
# nft add rule inet nat FORWARD tcp flags syn counter tcp option maxseg size set 1424
# nft add rule inet nat FORWARD tcp flags syn counter tcp option maxseg size set 1360
nft add rule inet nat FORWARD tcp flags syn counter tcp option maxseg size set rt mtu
nft add rule inet nat FORWARD ct state { related, established } counter packets 0 bytes 0 accept
nft add rule inet nat FORWARD ct status dnat accept
# accept all but the interface binded to ppp(enp1s0f3)
nft add rule inet nat FORWARD iifname "$ROUTER_LOCAL_LAN_INTERFACE" accept
# These rules will conflict with other firewall services such firewalld
# nft add rule inet nat FORWARD ip6 daddr { ::/96, ::ffff:0.0.0.0/96, 2002::/24, 2002:a00::/24, 2002:7f00::/24, 2002:a9fe::/32, 2002:ac10::/28, 2002:c0a8::/32, 2002:e000::/19 } reject with icmpv6 type addr-unreachable
# nft add rule inet nat FORWARD ct state { invalid } drop
# nft add rule inet nat FORWARD reject with icmpx type admin-prohibited

### Setup - ipv4
nft list chain ip nat PREROUTING >/dev/null 2>&1
if [[ $? -ne 0 ]]; then
  nft add chain ip nat PREROUTING { type nat hook prerouting priority dstnat \; }
fi
nft list chain ip nat POSTROUTING >/dev/null 2>&1
if [[ $? -ne 0 ]]; then
  nft add chain ip nat POSTROUTING { type nat hook postrouting priority srcnat \; }
fi
nft flush chain ip nat PREROUTING
nft flush chain ip nat POSTROUTING

### Source NAT - ipv4
# nft add rule ip nat POSTROUTING ip saddr 172.23.0.0/16 ip daddr != 172.23.0.0/16 snat to 1.2.3.4
# nft add rule nat POSTROUTING meta iifname enp1s0f1 counter packets 0 bytes 0 masquerade
# Skip local address when DSL interface get a local address
nft add rule ip nat POSTROUTING ip saddr @DEFAULT_ROUTE_IPV4 return
nft add rule ip nat POSTROUTING meta l4proto udp ip saddr @LOCAL_IPV4 ip daddr != @LOCAL_IPV4 ip daddr != '{ 224.0.0.0/4, 255.255.255.255/32 }' counter packets 0 bytes 0 masquerade to :16000-65535
# 172.20.1.1/24 is used for remote debug
nft add rule ip nat POSTROUTING meta l4proto tcp ip saddr @LOCAL_IPV4 ip daddr != @LOCAL_IPV4 ip daddr != '{ 224.0.0.0/4, 255.255.255.255/32, 172.20.1.1/24 }' counter packets 0 bytes 0 masquerade to :16000-65535
nft add rule ip nat POSTROUTING ip saddr @LOCAL_IPV4 ip daddr != @LOCAL_IPV4 ip daddr != '{ 224.0.0.0/4, 255.255.255.255/32 }' counter packets 0 bytes 0 masquerade

### Destination NAT - ipv4 - ssh
# nft add rule ip nat PREROUTING ip saddr != @LOCAL_IPV4 tcp dport 22 drop
# nft add rule ip nat PREROUTING ip saddr != @LOCAL_IPV4 tcp dport 36000 dnat to 172.23.1.1 :22

if [[ $NAT_SETUP_SKIP_IPV6 -eq 0 ]]; then
  ### Setup NAT - ipv6
  nft list chain ip6 nat PREROUTING >/dev/null 2>&1
  if [[ $? -ne 0 ]]; then
    nft add chain ip6 nat PREROUTING { type nat hook prerouting priority dstnat \; }
  fi
  nft list chain ip6 nat POSTROUTING >/dev/null 2>&1
  if [[ $? -ne 0 ]]; then
    nft add chain ip6 nat POSTROUTING { type nat hook postrouting priority srcnat \; }
  fi
  nft flush chain ip6 nat PREROUTING
  nft flush chain ip6 nat POSTROUTING

  ### Source NAT - ipv6
  # Skip local address when DSL interface get a local address
  nft add rule ip6 nat POSTROUTING ip saddr @DEFAULT_ROUTE_IPV6 return
  nft add rule ip6 nat POSTROUTING meta l4proto tcp ip6 saddr @LOCAL_IPV6 ip6 daddr != @LOCAL_IPV6 ip6 daddr != '{ff00::/8}' counter packets 0 bytes 0 masquerade to :16000-65535
  nft add rule ip6 nat POSTROUTING meta l4proto udp ip6 saddr @LOCAL_IPV6 ip6 daddr != @LOCAL_IPV6 ip6 daddr != '{ff00::/8}' counter packets 0 bytes 0 masquerade to :16000-65535
  nft add rule ip6 nat POSTROUTING ip6 saddr @LOCAL_IPV6 ip6 daddr != @LOCAL_IPV6 ip6 daddr != '{ff00::/8}' counter packets 0 bytes 0 masquerade

  ### Destination NAT - ipv6
  # nft add rule ip6 nat PREROUTING ip6 saddr != @LOCAL_IPV6 tcp dport 22 drop
  # nft add rule ip6 nat PREROUTING ip6 saddr != @LOCAL_IPV6 tcp dport 36000 dnat to fd27:32d6:ac12:18::1 :22
  # nft add rule ip6 nat PREROUTING ip6 saddr != @LOCAL_IPV6 tcp dport 36000 redirect to :22
fi
