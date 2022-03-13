#!/bin/bash

if [[ -e "/opt/nftables/sbin" ]]; then
  export PATH=/opt/nftables/sbin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/bin/site_perl:/usr/bin/vendor_perl:/usr/bin/core_perl
else
  export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/bin/site_perl:/usr/bin/vendor_perl:/usr/bin/core_perl
fi

SCRIPT_DIR="$(
  cd "$(dirname "$0")"
  pwd
)"

if [[ "x$ROUTER_HOME" == "x" ]]; then
  source "$SCRIPT_DIR/../configure-router.sh"
fi

if [[ -e "/lib/systemd/system" ]]; then
  export SETUP_SYSTEMD_SYSTEM_DIR=/lib/systemd/system
elif [[ -e "/usr/lib/systemd/system" ]]; then
  export SETUP_SYSTEMD_SYSTEM_DIR=/usr/lib/systemd/system
elif [[ -e "/etc/systemd/system" ]]; then
  export SETUP_SYSTEMD_SYSTEM_DIR=/etc/systemd/system
fi

if [[ "x$DNSMASQ_DNS_PORT" == "x" ]]; then
  DNSMASQ_DNS_PORT=53
fi

sed -i -r 's/#?DNSStubListener[[:space:]]*=.*/DNSStubListener=no/g' /etc/systemd/resolved.conf

systemctl disable systemd-resolved
systemctl stop systemd-resolved

# Test ipv6
ROUTER_CONFIG_IPV6_INTERFACES=()
# TYPE=bridge/ppp/ethernet/loopback
# for TEST_INERFACE in $(nmcli --fields=DEVICE,TYPE d status | awk '$2 == "bridge" {print $1}'); do
for TEST_INERFACE in $(nmcli --fields=DEVICE,TYPE d status | awk '$2 == "ppp" {print $1}'); do
  TEST_IPV6_ADDRESS=($(ip -6 -o addr show scope global dev "$TEST_INERFACE" | awk '{ print $2 }' | uniq))
  if [[ ${#TEST_IPV6_ADDRESS[@]} -gt 0 ]]; then
    ROUTER_CONFIG_IPV6_INTERFACES=(${ROUTER_CONFIG_IPV6_INTERFACES[@]} "$TEST_INERFACE")
  fi
done

# Doc: http://www.thekelleys.org.uk/dnsmasq/docs/dnsmasq-man.html
mkdir -p /etc/dnsmasq.d

echo '
#domain-needed
#interface=br0
#interface=pptp*

# bogus-priv
# dnssec

# strict-order
expand-hosts

no-poll
no-resolv

log-queries
log-dhcp
log-async=50
#log-facility=/var/log/dnsmasq-debug.log

' >/etc/dnsmasq.d/router.conf

echo "
port=$DNSMASQ_DNS_PORT
# Redirect to smartdns, which is the fastest but close AAAA address
server=127.0.0.1#$SMARTDNS_DNS_PORT
" >>/etc/dnsmasq.d/router.conf

echo '
# see https://www.dnsperf.com/#!dns-resolvers for DNS ranking
# ipv4
## Cloudflare
# server=1.1.1.1
# server=1.0.0.1
## Google
# server=8.8.8.8
# server=8.8.4.4
## Quad9
# server=9.9.9.9
# glibc only use 3 dns server
## aliyun
server=223.5.5.5
## DNSPod
server=119.29.29.29

## Baidu
# server=180.76.76.76

' >>/etc/dnsmasq.d/router.conf

# echo '
# #address=/shkits.com/104.27.145.8
# #address=/shkits.com/2606:4700:30::681b:9108
# ' > /etc/dnsmasq.d/custom.conf

echo '# ============ generated by docker-setup/setup-router ============
search localhost

options timeout:3

# see https://www.dnsperf.com/#!dns-resolvers for DNS ranking
# ipv4
## Cloudflare
# nameserver 1.1.1.1
# nameserver 1.0.0.1
## Google
# nameserver 8.8.8.8
# nameserver 8.8.4.4
## Quad9
# nameserver 9.9.9.9
# glibc only use 3 dns server
## aliyun
nameserver 223.5.5.5
nameserver 223.6.6.6
## DNSPod
nameserver 119.29.29.29
## Baidu
nameserver 180.76.76.76

options timeout:3
' >/etc/resolv.conf

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

if [[ ${#ROUTER_CONFIG_IPV6_INTERFACES[@]} -gt 0 ]]; then
  echo '
# ipv6
## Google
# nameserver 2001:4860:4860::8888
# nameserver 2001:4860:4860::8844
## Quad9
# nameserver 2620:fe::fe
# nameserver 2620:fe::9
## DNSPod
nameserver 2402:4e00::
## aliyun
nameserver 2400:3200::1
nameserver 2400:3200:baba::1
## Cloudflare
nameserver 2606:4700:4700::1111
nameserver 2606:4700:4700::1001
## biigroup
# nameserver 240c::6666
' >>/etc/resolv.conf
  echo "

# ipv6
## Google
# server=2001:4860:4860::8888
# server=2001:4860:4860::8844
## Quad9
# server=2620:fe::fe
# server=2620:fe::9
## DNSPod
server=2402:4e00::
## aliyun
server=2400:3200::1
server=2400:3200:baba::1
## Cloudflare
server=2606:4700:4700::1111
server=2606:4700:4700::1001
## biigroup
# server=240c::6666

" >>/etc/dnsmasq.d/router.conf
fi

echo "
# domain home.shkits.com
# dhcp-fqdn # Require domain to enable this
bind-dynamic
# Address not available with pppd 2.4.9
# see https://forum.openwrt.org/t/ppp-and-dnsmasq-issue/91475
except-interface=ppp0
except-interface=ppp1
# ipv4
dhcp-range=172.18.11.1,172.18.255.254,255.255.0.0,28800s
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
# https://thekelleys.org.uk/gitweb/?p=dnsmasq.git;a=blob_plain;f=src/dhcp-common.c
dhcp-option=option:router,172.18.1.10
dhcp-option=option:dns-server,172.18.1.10
dhcp-option=option:netbios-ns,0.0.0.0
" >>/etc/dnsmasq.d/router.conf

if [[ ${#ROUTER_CONFIG_IPV6_INTERFACES[@]} -gt 0 ]]; then
  # Do not us fc00::/7 for ipv6 here, some system think unique local address is not reachable from internet
  # We use dd27:32d6:ac12::/64 here for NAT, just like openwrt
  echo "
# ipv6
# dhcp-host for DHCPv6 seems not available
# dhcp-host=a0:36:9f:07:3f:98,[::010a]
# dhcp-option=option6:dns-server,dd27:32d6:ac12::010a
# dhcp-option=option6:domain-search,home.shkits.com

# https://listman.redhat.com/archives/libvir-list/2016-June/msg01065.html
# ra-param=*,0,0
enable-ra
dhcp-authoritative
# Using ndppd is a better replacement
# dhcp-script=/etc/dnsmasq.d/ipv6-ndpp.sh
" >>/etc/dnsmasq.d/router.conf

  # Required net.ipv6.conf.all.proxy_ndp=1
  echo "#!/bin/bash
ACTION=\"\$1\"
IP_ADDRESS=\"\$3\"
ROUTER_CONFIG_IPV6_INTERFACES=(${ROUTER_CONFIG_IPV6_INTERFACES[@]})
" >/etc/dnsmasq.d/ipv6-ndpp.sh
  echo '
case "$IP_ADDRESS" in
  *:*) ;;
  *) exit ;; # Skip ipv4
esac

case "$ACTION" in
  add|old)
    for SELECT_INTERFACE in ${ROUTER_CONFIG_IPV6_INTERFACES[@]}; do
        ip -6 route get "$IP_ADDRESS" oif "$SELECT_INTERFACE" 2>/dev/null && ip -6 neigh add proxy "$IP_ADDRESS" dev "$SELECT_INTERFACE"
    done
    ;;
  del)
    for SELECT_INTERFACE in ${ROUTER_CONFIG_IPV6_INTERFACES[@]}; do
        ip -6 route get "$IP_ADDRESS" oif "$SELECT_INTERFACE" 2>/dev/null && ip -6 neigh del proxy "$IP_ADDRESS" dev "$SELECT_INTERFACE"
    done
    ;;
esac
' >>/etc/dnsmasq.d/ipv6-ndpp.sh
  chmod +x /etc/dnsmasq.d/ipv6-ndpp.sh

  for IPV6_INTERFACE in ${ROUTER_CONFIG_IPV6_INTERFACES[@]}; do
    echo "
# dhcp-range=dd27:32d6:ac12::0003:0301,dd27:32d6:ac12::ffff:fffe,ra-names,slaac,64,28800s
dhcp-range=::0003:0301,::ffff:fffe,constructor:$ROUTER_CONFIG_IPV6_INTERFACE,ra-names,slaac,64,28800s
" >>/etc/dnsmasq.d/router.conf
  done

fi

echo 'conf-dir=/etc/dnsmasq.d/,*.router.conf' >>/etc/dnsmasq.d/router.conf

# Test: dhclient -n enp1s0f0 enp1s0f1 / dhclient -6 -n enp1s0f0 enp1s0f1

# Some system already has dnsmasq.service
if [[ -e "$SETUP_SYSTEMD_SYSTEM_DIR/dnsmasq.service" ]] && [[ ! -e "$SETUP_SYSTEMD_SYSTEM_DIR/dnsmasq.service.bak" ]]; then
  systemctl disbale dnsmasq
  systemctl stop dnsmasq
  mv $SETUP_SYSTEMD_SYSTEM_DIR/dnsmasq.service $SETUP_SYSTEMD_SYSTEM_DIR/dnsmasq.service.bak
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
ExecStartPre=/usr/sbin/dnsmasq -R -C /etc/dnsmasq.d/router.conf -x /var/run/dnsmasq-router.pid --test
ExecStart=/usr/sbin/dnsmasq -R -C /etc/dnsmasq.d/router.conf -x /var/run/dnsmasq-router.pid
ExecReload=/bin/kill -HUP $MAINPID

[Install]
WantedBy=multi-user.target
" >$SETUP_SYSTEMD_SYSTEM_DIR/dnsmasq.service

cp -f /etc/resolv.conf /etc/resolv.conf.dnsmasq

which ipset >/dev/null 2>&1
if [[ $? -eq 0 ]]; then
  ipset list DNSMASQ_GFW_IPV4 >/dev/null 2>&1
  if [[ $? -ne 0 ]]; then
    ipset create DNSMASQ_GFW_IPV4 hash:ip family inet
  fi

  ipset flush DNSMASQ_GFW_IPV4

  ipset list DNSMASQ_GFW_IPV6 >/dev/null 2>&1
  if [[ $? -ne 0 ]]; then
    ipset create DNSMASQ_GFW_IPV6 hash:ip family inet6
  fi

  ipset flush DNSMASQ_GFW_IPV6
fi