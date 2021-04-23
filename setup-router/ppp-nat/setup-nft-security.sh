#!/bin/bash

nft list table inet security_firewall > /dev/null 2>&1 ;
if [[ $? -eq 0 ]]; then
    nft delete table inet security_firewall ;
fi
nft add table inet security_firewall ;


nft add table inet security_firewall ;



nft add chain inet security_firewall PREROUTING { type filter hook prerouting priority raw + 10\; policy accept\; }
nft add rule inet security_firewall PREROUTING icmpv6 type { nd-router-advert, nd-neighbor-solicit } accept ;
nft add rule inet security_firewall PREROUTING meta nfproto ipv6 fib saddr . iif oif missing drop ;



nft add chain inet security_firewall INPUT { type filter hook input priority filter + 10\; policy accept\; }
nft add rule inet security_firewall INPUT ct state { established, related } accept
nft add rule inet security_firewall INPUT ct status dnat accept
nft add rule inet security_firewall INPUT iifname { lo, br0, enp1s0f0, enp1s0f1, enp5s0 } accept
# Internal services -- begin
nft add rule inet security_firewall INPUT ip saddr {127.0.0.1/32, 192.168.0.0/16, 172.16.0.0/12, 10.0.0.0/8} tcp dport 22 ct state { new, untracked } accept
nft add rule inet security_firewall INPUT ip6 saddr {::1/128, fc00::/7, fe80::/10, fd00::/8, ff00::/8} tcp dport 22 ct state { new, untracked } accept
nft add rule inet security_firewall INPUT ip6 daddr fe80::/64 udp dport 546 ct state { new, untracked } accept
nft add rule inet security_firewall INPUT tcp dport 53 ct state { new, untracked } accept
nft add rule inet security_firewall INPUT udp dport 53 ct state { new, untracked } accept
nft add rule inet security_firewall INPUT udp dport 67 ct state { new, untracked } accept
nft add rule inet security_firewall INPUT udp dport 547 ct state { new, untracked } accept
nft add rule inet security_firewall INPUT tcp dport 853 ct state { new, untracked } accept
nft add rule inet security_firewall INPUT udp dport 6881 ct state { new, untracked } accept
nft add rule inet security_firewall INPUT tcp dport 6881 ct state { new, untracked } accept
nft add rule inet security_firewall INPUT udp dport 6882 ct state { new, untracked } accept
nft add rule inet security_firewall INPUT tcp dport 6882 ct state { new, untracked } accept
nft add rule inet security_firewall INPUT udp dport 6883 ct state { new, untracked } accept
nft add rule inet security_firewall INPUT tcp dport 6883 ct state { new, untracked } accept
nft add rule inet security_firewall INPUT udp dport 8371 ct state { new, untracked } accept
nft add rule inet security_firewall INPUT tcp dport 8371 ct state { new, untracked } accept
nft add rule inet security_firewall INPUT udp dport 8372 ct state { new, untracked } accept
nft add rule inet security_firewall INPUT tcp dport 8372 ct state { new, untracked } accept
nft add rule inet security_firewall INPUT udp dport 8381 ct state { new, untracked } accept
nft add rule inet security_firewall INPUT tcp dport 8381 ct state { new, untracked } accept
nft add rule inet security_firewall INPUT udp dport 8382 ct state { new, untracked } accept
nft add rule inet security_firewall INPUT tcp dport 8382 ct state { new, untracked } accept
nft add rule inet security_firewall INPUT tcp dport 36000 ct state { new, untracked } accept
# Internal services -- end
nft add rule inet security_firewall INPUT meta l4proto { icmp, ipv6-icmp } accept
nft add rule inet security_firewall INPUT ct state { invalid } drop
nft add rule inet security_firewall INPUT reject with icmpx type admin-prohibited



nft add chain inet security_firewall OUTPUT { type filter hook output priority filter + 10\; policy accept\; }
nft add rule inet security_firewall OUTPUT  oifname "lo" accept
nft add rule inet security_firewall OUTPUT  ip6 daddr { ::/96, ::ffff:0.0.0.0/96, 2002::/24, 2002:a00::/24, 2002:7f00::/24, 2002:a9fe::/32, 2002:ac10::/28, 2002:c0a8::/32, 2002:e000::/19 } reject with icmpv6 type addr-unreachable



nft add chain inet security_firewall FORWARD { type filter hook forward priority filter + 10\; policy accept\; }
nft add rule inet security_firewall FORWARD  ct state { established, related } accept
nft add rule inet security_firewall FORWARD  ct status dnat accept
nft add rule inet security_firewall FORWARD  iifname { lo, br0, enp1s0f0, enp1s0f1, enp5s0 } accept
nft add rule inet security_firewall FORWARD  ip6 daddr { ::/96, ::ffff:0.0.0.0/96, 2002::/24, 2002:a00::/24, 2002:7f00::/24, 2002:a9fe::/32, 2002:ac10::/28, 2002:c0a8::/32, 2002:e000::/19 } reject with icmpv6 type addr-unreachable
#
nft add rule inet security_firewall FORWARD  meta l4proto { icmp, ipv6-icmp } accept
nft add rule inet security_firewall FORWARD  ct state { new, untracked } accept
#
nft add rule inet security_firewall FORWARD  ct state { invalid } drop
nft add rule inet security_firewall FORWARD  reject with icmpx type admin-prohibited
