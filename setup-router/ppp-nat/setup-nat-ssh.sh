#!/bin/bash

if [ -e "/opt/nftables/sbin" ]; then
    export PATH=/opt/nftables/sbin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/bin/site_perl:/usr/bin/vendor_perl:/usr/bin/core_perl
else
    export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/bin/site_perl:/usr/bin/vendor_perl:/usr/bin/core_perl
fi

which firewall-cmd > /dev/null 2>&1 ;

if [ $? -eq 0 ]; then
    firewall-cmd --permanent --add-masquerade ;

    echo '<?xml version="1.0" encoding="utf-8"?>
<service>
    <short>redirect-sshd</short>
    <description>Redirect sshd</description>
    <port port="36000" protocol="tcp"/>
    <port port="36001" protocol="tcp"/>
</service>
' | tee /etc/firewalld/services/redirect-sshd.xml ;

    firewall-cmd --permanent --add-service=ssh ;
    firewall-cmd --permanent --add-service=redirect-sshd ;
    firewall-cmd --reload ;
    firewall-cmd --query-masquerade ;
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

### Setup - ipv4&ipv6
nft list chain inet nat filter > /dev/null 2>&1 ;
if [ $? -ne 0 ]; then
    nft add chain inet nat filter { type filter hook forward priority 0 \; }
fi
nft flush chain inet nat filter
nft add rule inet nat filter ct state { related, established } counter packets 0 bytes 0 accept
nft add rule inet nat filter ct status dnat accept
# accept all but the interface binded to ppp(enp1s0f3)
nft add rule inet nat filter iifname { lo, enp1s0f0, enp1s0f1, enp5s0 } accept
# These rules will conflict with other firewall services such firewalld
# nft add rule inet nat filter ip6 daddr { ::/96, ::ffff:0.0.0.0/96, 2002::/24, 2002:a00::/24, 2002:7f00::/24, 2002:a9fe::/32, 2002:ac10::/28, 2002:c0a8::/32, 2002:e000::/19 } reject with icmpv6 type addr-unreachable
# nft add rule inet nat filter ct state { invalid } drop
# nft add rule inet nat filter reject with icmpx type admin-prohibited

### Setup - ipv4
nft list chain ip nat prerouting > /dev/null 2>&1 ;
if [ $? -ne 0 ]; then
    nft add chain ip nat prerouting { type nat hook prerouting priority 0 \; }
fi
nft list chain ip nat postrouting > /dev/null 2>&1 ;
if [ $? -ne 0 ]; then
    nft add chain ip nat postrouting { type nat hook postrouting priority 100 \; }
fi
nft flush chain ip nat prerouting
nft flush chain ip nat postrouting

### Source NAT - ipv4
# nft add rule ip nat postrouting ip saddr 172.18.0.0/16 ip daddr != 172.18.0.0/16 snat to 1.2.3.4
# nft add rule nat postrouting meta iifname enp1s0f1 counter packets 0 bytes 0 masquerade
nft add rule ip nat postrouting ip saddr 172.18.0.0/16 ip daddr != 172.18.0.0/16 counter packets 0 bytes 0 masquerade

### Destination NAT - ipv4 - ssh
nft add rule ip nat prerouting ip saddr != 172.18.0.0/16 tcp dport 36000 dnat to 172.18.1.1 :22
# nft add rule ip nat prerouting ip saddr != 172.18.0.0/16 tcp dport 36001 dnat to 172.18.1.10 :22
# nft add rule ip nat prerouting meta iif enp1s0f0 tcp dport 36000 redirect to :22


### Setup NAT - ipv6
nft list chain ip6 nat prerouting > /dev/null 2>&1 ;
if [ $? -ne 0 ]; then
    nft add chain ip6 nat prerouting { type nat hook prerouting priority 0 \; }
fi
nft list chain ip6 nat postrouting > /dev/null 2>&1 ;
if [ $? -ne 0 ]; then
    nft add chain ip6 nat postrouting { type nat hook postrouting priority 100 \; }
fi
nft flush chain ip6 nat prerouting
nft flush chain ip6 nat postrouting

### Source NAT - ipv6
nft add rule ip6 nat postrouting ip6 saddr fd27:32d6:ac12::/48 ip6 daddr != fd27:32d6:ac12::/48 counter packets 0 bytes 0 masquerade

### Destination NAT - ipv6
nft add rule ip6 nat prerouting ip6 saddr != fd27:32d6:ac12::/48 tcp dport 36000 dnat to fd27:32d6:ac12:18::1 :22
