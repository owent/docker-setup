#!/bin/bash

# nftables
# Quick: https://wiki.nftables.org/wiki-nftables/index.php/Performing_Network_Address_Translation_(NAT)
# Quick(CN): https://wiki.archlinux.org/index.php/Nftables_(%E7%AE%80%E4%BD%93%E4%B8%AD%E6%96%87)#Masquerading
# List all tables/chains/rules/matches/statements: https://wiki.nftables.org/wiki-nftables/index.php/Quick_reference-nftables_in_10_minutes#Rules
# man 8 nft

## NAT
nft add table nat
nft add chain nat prerouting { type nat hook prerouting priority 0 \; }
nft add chain nat postrouting { type nat hook postrouting priority 100 \; }

### Source NAT
# nft add rule nat postrouting ip saddr 172.18.0.0/16 ip daddr != 172.18.0.0/16 snat to 1.2.3.4
# nft add rule nat postrouting meta iifname enp1s0f1 counter packets 0 bytes 0 masquerade
nft add rule nat postrouting ip saddr 172.18.0.0/16 ip daddr != 172.18.0.0/16 counter packets 0 bytes 0 masquerade
nft add rule nat postrouting meta l4proto tcp ip saddr 172.18.0.0/16 ip daddr != 172.18.0.0/16 counter packets 0 bytes 0 masquerade to :1024-65535
nft add rule nat postrouting meta l4proto udp ip saddr 172.18.0.0/16 ip daddr != 172.18.0.0/16 counter packets 0 bytes 0 masquerade to :1024-65535

### Destination NAT
nft add rule nat prerouting ip saddr != 172.18.0.0/16 tcp dport 36000 dnat to 172.18.1.1 :22
nft add rule nat prerouting ip saddr != 172.18.0.0/16 tcp dport 36001 dnat to 172.18.1.11 :22
# nft add rule nat prerouting meta iif enp1s0f0 tcp dport 36000 redirect to :22
