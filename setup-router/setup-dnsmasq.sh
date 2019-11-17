#!/bin/bash

# Doc: http://www.thekelleys.org.uk/dnsmasq/docs/dnsmasq-man.html

echo '
port=53

domain-needed
bind-dynamic
#interface=br0
#interface=pptp*

bogus-priv
# dnssec

strict-order
expand-hosts

no-poll
no-resolv

#log-queries
#log-dhcp
#log-facility=/var/log/dnsmasq-debug.log

# see https://www.dnsperf.com/#!dns-resolvers for DNS ranking
# ipv4
## Cloudflare
server=1.1.1.1
server=1.0.0.1
## Google
server=8.8.8.8
server=8.8.4.4
## Quad9
server=9.9.9.9
## aliyun
server=223.5.5.5
server=223.6.6.6
## DNSPod
server=119.29.29.29
## Baidu
server=180.76.76.76

# ipv6
## Cloudflare
server=2606:4700:4700::1111
server=2606:4700:4700::1001
## Google
server=2001:4860:4860::8888
server=2001:4860:4860::8844
## Quad9
server=2620:fe::fe
server=2620:fe::9
' > /etc/dnsmasq.d/router.conf

# echo '
# #address=/ouri.app/104.27.145.8
# #address=/ouri.app/2606:4700:30::681b:9108
# ' > /etc/dnsmasq.d/custom.conf

echo 'search localhost

# see https://www.dnsperf.com/#!dns-resolvers for DNS ranking
# ipv4
## Cloudflare
nameserver 1.1.1.1
nameserver 1.0.0.1
## Google
nameserver 8.8.8.8
nameserver 8.8.4.4
## Quad9
nameserver 9.9.9.9
## aliyun
nameserver 223.5.5.5
nameserver 223.6.6.6
## DNSPod
nameserver 119.29.29.29
## Baidu
nameserver 180.76.76.76

# ipv6
## Cloudflare
nameserver 2606:4700:4700::1111
nameserver 2606:4700:4700::1001
## Google
nameserver 2001:4860:4860::8888
nameserver 2001:4860:4860::8844
## Quad9
nameserver 2620:fe::fe
nameserver 2620:fe::9
' > /etc/resolv.conf ;

# setup dns over https and store into ipset gfwlist/router/white_list/black_list
# https://dnscrypt.info/
# https://dnscrypt.info/implementations/
# DOH whitelist
# echo '
# # Domians over dnscrypt-proxy
# #for router itself
# server=/.google.com.tw/127.0.0.1#5300
# ipset=/.google.com.tw/router
# server=/dns.google.com/127.0.0.1#5300
# ipset=/dns.google.com/router
# server=/.github.com/127.0.0.1#5300
# ipset=/.github.com/router
# server=/.github.io/127.0.0.1#5300
# ipset=/.github.io/router
# server=/.raw.githubusercontent.com/127.0.0.1#5300
# ipset=/.raw.githubusercontent.com/router
# server=/.adblockplus.org/127.0.0.1#5300
# ipset=/.adblockplus.org/router
# server=/.entware.net/127.0.0.1#5300
# ipset=/.entware.net/router
# server=/.apnic.net/127.0.0.1#5300
# ipset=/.apnic.net/router
# #for special site
# server=/.apple.com/119.29.29.29#53
# ipset=/.apple.com/white_list
# server=/.microsoft.com/119.29.29.29#53
# ipset=/.microsoft.com/white_list
# #for black_domain
# server=/.fonts.googleapis.com/127.0.0.1#5300
# ipset=/.fonts.googleapis.com/black_list
# server=/.ghs.googlehosted.com/127.0.0.1#5300
# ipset=/.ghs.googlehosted.com/black_list
# server=/.steamcommunity.com/127.0.0.1#5300
# ipset=/.steamcommunity.com/black_list
# server=/.store.steampowered.com/127.0.0.1#5300
# ipset=/.store.steampowered.com/black_list
# server=/.cdn.rubyinstaller.org/127.0.0.1#5300
# ipset=/.cdn.rubyinstaller.org/black_list
# server=/.download.mobatek.net/127.0.0.1#5300
# ipset=/.download.mobatek.net/black_list
# server=/.googleapis.cn/127.0.0.1#5300
# ipset=/.googleapis.cn/black_list
# server=/.services.googleapis.com/127.0.0.1#5300
# ipset=/.services.googleapis.com/black_list
# server=/.github.githubassets.com/127.0.0.1#5300
# ipset=/.github.githubassets.com/black_list
# server=/.developer.github.com/127.0.0.1#5300
# ipset=/.developer.github.com/black_list
# server=/.battle.net/127.0.0.1#5300
# ipset=/.battle.net/black_list
# server=/.us.battle.net/127.0.0.1#5300
# ipset=/.us.battle.net/black_list
# server=/.us.shop.battle.net/127.0.0.1#5300
# ipset=/.us.shop.battle.net/black_list
# server=/.us-legal.battle.net/127.0.0.1#5300
# ipset=/.us-legal.battle.net/black_list
# server=/.kr.actual.battle.net/127.0.0.1#5300
# ipset=/.kr.actual.battle.net/black_list
# server=/.kr.version.battle.net/127.0.0.1#5300
# ipset=/.kr.version.battle.net/black_list
# server=/.kr.patch.battle.net/127.0.0.1#5300
# ipset=/.kr.patch.battle.net/black_list
# ' >> /etc/dnsmasq.d/router.conf


# domain=lan
# expand-hosts
# bogus-priv
# local=/lan/
# dhcp-range=lan,172.18.3.1,172.18.255.254,255.255.0.0,86400s
# dhcp-option=lan,3,172.18.1.2
# dhcp-option=lan,15,lan
# dhcp-option=lan,44,0.0.0.0
# dhcp-option=lan,252,"\n"
# ra-param=br0,10,600
# enable-ra
# quiet-ra
# dhcp-range=lan,::,constructor:br0,ra-only,64,600
# dhcp-option=lan,option6:23,[::]
# dhcp-option=lan,option6:24,lan
# dhcp-authoritative

systemctl enable dnsmasq

systemctl start dnsmasq
