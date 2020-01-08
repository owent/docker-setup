#!/bin/bash

if [ -e "/opt/nftables/sbin" ]; then
    export PATH=/opt/nftables/sbin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/bin/site_perl:/usr/bin/vendor_perl:/usr/bin/core_perl
else
    export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/bin/site_perl:/usr/bin/vendor_perl:/usr/bin/core_perl
fi

echo "
net.ipv4.ip_forward=1
net.ipv4.conf.all.forwarding=1
net.ipv4.conf.default.forwarding=1
net.ipv6.conf.all.forwarding=1
net.ipv6.conf.default.forwarding=1
" > /etc/sysctl.d/91-forwarding.conf ;
sysctl -p ;

# nftables
# Quick: https://wiki.nftables.org/wiki-nftables/index.php/Performing_Network_Address_Translation_(NAT)
# Quick(CN): https://wiki.archlinux.org/index.php/Nftables_(%E7%AE%80%E4%BD%93%E4%B8%AD%E6%96%87)#Masquerading
# List all tables/chains/rules/matches/statements: https://wiki.nftables.org/wiki-nftables/index.php/Quick_reference-nftables_in_10_minutes#Rules
# man 8 nft: 
#    https://www.netfilter.org/projects/nftables/manpage.html
#    https://www.mankier.com/8/nft
# Note:
#     using ```find /lib/modules/$(uname -r) -type f -name '*.ko'``` to see all available modules


## NAT
# just like iptables -t nat
nft add table nat

### Setup - ipv4
nft add chain nat prerouting { type nat hook prerouting priority 0 \; }
nft add chain nat postrouting { type nat hook postrouting priority 100 \; }

### Source NAT - ipv4
# nft add rule nat postrouting ip saddr 172.18.0.0/16 ip daddr != 172.18.0.0/16 snat to 1.2.3.4
# nft add rule nat postrouting meta iifname enp1s0f1 counter packets 0 bytes 0 masquerade
nft add rule nat postrouting ip saddr 172.18.0.0/16 ip daddr != 172.18.0.0/16 counter packets 0 bytes 0 masquerade
nft add rule nat postrouting meta l4proto {tcp, udp} ip saddr 172.18.0.0/16 ip daddr != 172.18.0.0/16 counter packets 0 bytes 0 masquerade to :1024-65535

### Destination NAT - ipv4 - ssh
nft add rule nat prerouting ip saddr != 172.18.0.0/16 tcp dport 36000 dnat to 172.18.1.1 :22
# nft add rule nat prerouting ip saddr != 172.18.0.0/16 tcp dport 36001 dnat to 172.18.1.10 :22
# nft add rule nat prerouting meta iif enp1s0f0 tcp dport 36000 redirect to :22


### Setup NAT - ipv6
nft add chain ip6 nat prerouting { type nat hook prerouting priority 0 \; }
nft add chain ip6 nat postrouting { type nat hook postrouting priority 100 \; }

### Source NAT - ipv6
nft add rule ip6 nat postrouting ip6 saddr fd27:32d6:ac12::/48 ip6 daddr != fd27:32d6:ac12::/48 counter packets 0 bytes 0 masquerade
nft add rule ip6 nat postrouting meta l4proto {tcp, udp} ip6 saddr fd27:32d6:ac12::/48 ip6 daddr != fd27:32d6:ac12::/48 counter packets 0 bytes 0 masquerade to :1024-65535

### Destination NAT - ipv6
nft add rule ip6 nat prerouting ip saddr != fd27:32d6:ac12::/48 tcp dport 36000 dnat to fd27:32d6:ac12:18::1 :22

### firewall
# firewall-cmd --permanent --add-service=ssh
firewall-cmd --permanent --add-service=redirect-sshd
