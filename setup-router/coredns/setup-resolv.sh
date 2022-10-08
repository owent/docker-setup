#!/bin/bash

if [ -e "/etc/resolv.conf" ]; then
  cp -f /etc/resolv.conf /etc/resolv.conf.coredns
fi

echo '# ============ generated by docker-setup/setup-router/coredns/setup-resolv.sh ============
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
## DNSPod
nameserver 119.29.29.29
## Baidu
nameserver 180.76.76.76

' >/etc/resolv.conf

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

fi
