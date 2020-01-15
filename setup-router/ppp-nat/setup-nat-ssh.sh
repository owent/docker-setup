#!/bin/bash

if [ -e "/opt/nftables/sbin" ]; then
    export PATH=/opt/nftables/sbin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/bin/site_perl:/usr/bin/vendor_perl:/usr/bin/core_perl
else
    export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/bin/site_perl:/usr/bin/vendor_perl:/usr/bin/core_perl
fi

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

if [ "x" == "x$SETUP_WITH_DEBUG_LOG" ]; then
    SETUP_WITH_DEBUG_LOG=0
fi

## NAT
# just like iptables -t nat
nft list table ip nat > /dev/null 2>&1 ;
if [ $? -ne 0 ]; then
    nft add table ip nat
fi
nft list table ip6 nat > /dev/null 2>&1 ;
if [ $? -ne 0 ]; then
    nft add table ip6 nat
fi
nft list table inet nat > /dev/null 2>&1 ;
if [ $? -ne 0 ]; then
    nft add table inet nat
fi

#### ========== debug ==========
if [ $SETUP_WITH_DEBUG_LOG -ne 0 ]; then
    nft list table inet debug > /dev/null 2>&1 ;
    if [ $? -ne 0 ]; then
        nft add table inet debug
    fi
    nft list chain inet debug FORWARD > /dev/null 2>&1 ;
    if [ $? -ne 0 ]; then
        nft add chain inet debug FORWARD { type filter hook forward priority filter - 1 \; }
    fi
    nft flush chain inet debug FORWARD
    nft add rule inet debug FORWARD ip saddr 103.235.46.39/32 meta nftrace set 1
    nft add rule inet debug FORWARD ip saddr 103.235.46.39/32 log prefix '">>>TCP>>FORWARD:"' level debug flags all
    nft add rule inet debug FORWARD ip daddr 103.235.46.39/32 meta nftrace set 1
    nft add rule inet debug FORWARD ip daddr 103.235.46.39/32 log prefix '"<<<TCP<<FORWARD:"' level debug flags all
    nft list chain inet debug PREROUTING > /dev/null 2>&1 ;
    if [ $? -ne 0 ]; then
        nft add chain inet debug PREROUTING { type filter hook prerouting priority filter - 1 \; }
    fi
    nft flush chain inet debug PREROUTING
    nft add rule inet debug PREROUTING ip saddr 103.235.46.39/32 meta nftrace set 1
    nft add rule inet debug PREROUTING ip saddr 103.235.46.39/32 log prefix '">>>TCP>>PRERO:"' level debug flags all
    nft add rule inet debug PREROUTING ip daddr 103.235.46.39/32 meta nftrace set 1
    nft add rule inet debug PREROUTING ip daddr 103.235.46.39/32 log prefix '"<<<TCP<<PRERO:"' level debug flags all
    nft list chain inet debug OUTPUT > /dev/null 2>&1 ;
    if [ $? -ne 0 ]; then
        nft add chain inet debug OUTPUT { type filter hook output priority filter - 1 \; }
    fi
    nft flush chain inet debug OUTPUT
    nft add rule inet debug OUTPUT ip saddr 103.235.46.39/32 meta nftrace set 1
    nft add rule inet debug OUTPUT ip saddr 103.235.46.39/32 log prefix '">>>TCP>>OUTPUT:"' level debug flags all
    nft add rule inet debug OUTPUT ip daddr 103.235.46.39/32 meta nftrace set 1
    nft add rule inet debug OUTPUT ip daddr 103.235.46.39/32 log prefix '"<<<TCP<<OUTPUT:"' level debug flags all
else
    nft list table inet debug > /dev/null 2>&1 ;
    if [ $? -eq 0 ]; then
        nft delete table inet debug
    fi
fi

### Setup - ipv4&ipv6
nft list chain inet nat FORWARD > /dev/null 2>&1 ;
if [ $? -ne 0 ]; then
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
nft add rule inet nat FORWARD iifname { lo, br0, enp1s0f0, enp1s0f1, enp5s0 } accept
# These rules will conflict with other firewall services such firewalld
# nft add rule inet nat FORWARD ip6 daddr { ::/96, ::ffff:0.0.0.0/96, 2002::/24, 2002:a00::/24, 2002:7f00::/24, 2002:a9fe::/32, 2002:ac10::/28, 2002:c0a8::/32, 2002:e000::/19 } reject with icmpv6 type addr-unreachable
# nft add rule inet nat FORWARD ct state { invalid } drop
# nft add rule inet nat FORWARD reject with icmpx type admin-prohibited

### Setup - ipv4
nft list chain ip nat PREROUTING > /dev/null 2>&1 ;
if [ $? -ne 0 ]; then
    nft add chain ip nat PREROUTING { type nat hook prerouting priority dstnat \; }
fi
nft list chain ip nat POSTROUTING > /dev/null 2>&1 ;
if [ $? -ne 0 ]; then
    nft add chain ip nat POSTROUTING { type nat hook postrouting priority srcnat \; }
fi
nft flush chain ip nat PREROUTING
nft flush chain ip nat POSTROUTING

### Source NAT - ipv4
# nft add rule ip nat POSTROUTING ip saddr 172.18.0.0/16 ip daddr != 172.18.0.0/16 snat to 1.2.3.4
# nft add rule nat POSTROUTING meta iifname enp1s0f1 counter packets 0 bytes 0 masquerade
nft add rule ip nat POSTROUTING ip saddr {127.0.0.1/32, 192.168.0.0/16, 172.16.0.0/12, 10.0.0.0/8} ip daddr != {127.0.0.1/32, 192.168.0.0/16, 172.16.0.0/12, 10.0.0.0/8} counter packets 0 bytes 0 masquerade

### Destination NAT - ipv4 - ssh
nft add rule ip nat PREROUTING ip saddr != {127.0.0.1/32, 192.168.0.0/16, 172.16.0.0/12, 10.0.0.0/8} tcp dport 22 drop
nft add rule ip nat PREROUTING ip saddr != {127.0.0.1/32, 192.168.0.0/16, 172.16.0.0/12, 10.0.0.0/8} tcp dport 36000 dnat to 172.18.1.1 :22


### Setup NAT - ipv6
nft list chain ip6 nat PREROUTING > /dev/null 2>&1 ;
if [ $? -ne 0 ]; then
    nft add chain ip6 nat PREROUTING { type nat hook prerouting priority dstnat \; }
fi
nft list chain ip6 nat POSTROUTING > /dev/null 2>&1 ;
if [ $? -ne 0 ]; then
    nft add chain ip6 nat POSTROUTING { type nat hook postrouting priority srcnat \; }
fi
nft flush chain ip6 nat PREROUTING
nft flush chain ip6 nat POSTROUTING

### Source NAT - ipv6
nft add rule ip6 nat POSTROUTING ip6 saddr {::1/128, fc00::/7, fe80::/10, fd00::/8, ff00::/8} ip6 daddr != {::1/128, fc00::/7, fe80::/10, fd00::/8, ff00::/8} counter packets 0 bytes 0 masquerade

### Destination NAT - ipv6
nft add rule ip6 nat PREROUTING ip6 saddr != {::1/128, fc00::/7, fe80::/10, fd00::/8, ff00::/8} tcp dport 22 drop
nft add rule ip6 nat PREROUTING ip6 saddr != {::1/128, fc00::/7, fe80::/10, fd00::/8, ff00::/8} tcp dport 36000 dnat to fd27:32d6:ac12:18::1 :22
