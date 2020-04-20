#!/bin/bash

if [ -e "/opt/nftables/sbin" ]; then
    export PATH=/opt/nftables/sbin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/bin/site_perl:/usr/bin/vendor_perl:/usr/bin/core_perl
else
    export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/bin/site_perl:/usr/bin/vendor_perl:/usr/bin/core_perl
fi

# Doc: http://www.thekelleys.org.uk/dnsmasq/docs/dnsmasq-man.html
mkdir -p /etc/dnsmasq.d;

echo '
#domain-needed
#interface=br0
#interface=pptp*

# bogus-priv
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

# IPv6 - DHCPv6, it's require to configure a interface manually

if [ "x$ROUTER_CONFIG_IPV6_INTERFACE" != "x" ]; then
    echo '
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
' >> /etc/resolv.conf ;
    echo "

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

" >> /etc/dnsmasq.d/router.conf
fi

echo "
bind-dynamic
# ipv4
dhcp-range=172.18.11.1,172.18.255.254,255.255.0.0,86400s
dhcp-host=70:85:c2:dc:0c:87,172.18.1.1
dhcp-host=a0:36:9f:07:3f:98,172.18.1.10
dhcp-host=a0:36:9f:07:3f:99,172.18.1.11
dhcp-host=a0:36:9f:07:3f:9a,172.18.1.12
dhcp-host=a0:36:9f:07:3f:9b,172.18.1.13
dhcp-host=18:31:BF:A4:F0:30,172.18.2.1
dhcp-host=18:31:BF:A4:F0:31,172.18.2.2
dhcp-host=18:31:BF:A4:F0:34,172.18.2.3
dhcp-host=18:31:BF:A4:F0:38,172.18.2.4
# available options can be see by dnsmasq --help dhcp
# https://en.wikipedia.org/wiki/Dynamic_Host_Configuration_Protocol
# https://www.iana.org/assignments/bootp-dhcp-parameters/bootp-dhcp-parameters.xhtml
dhcp-option=3,172.18.1.10
dhcp-option=44,0.0.0.0
" >> /etc/dnsmasq.d/router.conf

if [ "x$ROUTER_CONFIG_IPV6_INTERFACE" != "x" ]; then
    echo "
# ipv6
# dhcp-range=fd27:32d6:ac12::0301,fd27:32d6:ac12::fffe,slaac,64,86400s
dhcp-range=::,constructor:$ROUTER_CONFIG_IPV6_INTERFACE,ra-names,64,86400s
# dhcp-host for DHCPv6 seems not available
# dhcp-host=70:85:c2:dc:0c:87,[::0101]

enable-ra
quiet-ra
dhcp-authoritative
" >> /etc/dnsmasq.d/router.conf
fi

echo 'conf-dir=/etc/dnsmasq.d/,*.router.conf' >> /etc/dnsmasq.d/router.conf;

# Test: dhclient -n enp1s0f0 enp1s0f1 / dhclient -6 -n enp1s0f0 enp1s0f1

# Some system already has dnsmasq.service
if [ -e "/lib/systemd/system/dnsmasq.service" ] && [ ! -e "/lib/systemd/system/dnsmasq.service.bak" ]; then
    systemctl disbale dnsmasq;
    systemctl stop dnsmasq;
    mv /lib/systemd/system/dnsmasq.service /lib/systemd/system/dnsmasq.service.bak;
fi
echo "
[Unit]
Description=dnsmasq - A lightweight DHCP and caching DNS server
Requires=network.target
Wants=nss-lookup.target
Before=nss-lookup.target
After=network.target

[Service]
Type=forking
PIDFile=/var/run/dnsmasq-router.pid

# Test the config file and refuse starting if it is not valid.
ExecStartPre=/usr/sbin/dnsmasq -r /etc/resolv.conf -C /etc/dnsmasq.d/router.conf -x /var/run/dnsmasq-router.pid --test
ExecStart=/usr/sbin/dnsmasq -r /etc/resolv.conf -C /etc/dnsmasq.d/router.conf -x /var/run/dnsmasq-router.pid
ExecReload=/bin/kill -HUP $MAINPID

[Install]
WantedBy=multi-user.target
" > $SETUP_SYSTEMD_SYSTEM_DIR/dnsmasq.service ;

which ipset > /dev/null 2>&1 ;
if [ $? -eq 0 ]; then
    ipset list DNSMASQ_GFW_IPV4 > /dev/null 2>&1 ;
    if [ $? -ne 0 ]; then
        ipset create DNSMASQ_GFW_IPV4 hash:ip family inet;
    fi

    ipset flush DNSMASQ_GFW_IPV4;

    ipset list DNSMASQ_GFW_IPV6 > /dev/null 2>&1 ;
    if [ $? -ne 0 ]; then
        ipset create DNSMASQ_GFW_IPV6 hash:ip family inet6;
    fi

    ipset flush DNSMASQ_GFW_IPV6;
fi
