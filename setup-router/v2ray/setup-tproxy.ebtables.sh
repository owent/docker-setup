#!/bin/bash

if [[ -e "/opt/nftables/sbin" ]]; then
  export PATH=/opt/nftables/sbin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/bin/site_perl:/usr/bin/vendor_perl:/usr/bin/core_perl
else
  export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/bin/site_perl:/usr/bin/vendor_perl:/usr/bin/core_perl
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../configure-router.sh"

set -x

if [[ "x" == "x$SETUP_WITH_DEBUG_LOG" ]]; then
  SETUP_WITH_DEBUG_LOG=0
fi

# Reset local ip address
source "$(cd "$(dirname "$0")" && cd .. && pwd)/reset-local-address-set.sh"

## Setup - bridge
ebtables -t broute -L V2RAY_BRIDGE >/dev/null 2>&1
if [[ $? -ne 0 ]]; then
  ebtables -t broute -N V2RAY_BRIDGE
else
  ebtables -t broute -F V2RAY_BRIDGE
fi

# for SKIP_PORT in $(echo $SETUP_WITH_INTERNAL_SERVICE_PORT | sed 's/,/ /g'); do
#     ebtables -t broute -A V2RAY_BRIDGE -p ipv4 --ip-sport $SKIP_PORT -j RETURN
#     if [[ $TPROXY_SETUP_WITHOUT_IPV6 -eq 0 ]]; then
#         ebtables -t broute -A V2RAY_BRIDGE -p ipv6 --ip6-sport $SKIP_PORT -j RETURN
#     fi
# done

for SKIP_PORT in $(echo $ROUTER_INTERNAL_DIRECTLY_VISIT_UDP_DPORT | sed 's/,/ /g'); do
  ebtables -t broute -A V2RAY_BRIDGE -p ipv4 --ip-proto udp --ip-dport $SKIP_PORT -j RETURN
  if [[ $TPROXY_SETUP_WITHOUT_IPV6 -eq 0 ]]; then
    ebtables -t broute -A V2RAY_BRIDGE -p ipv6 --ip6-proto udp --ip6-dport $SKIP_PORT -j RETURN
  fi
done

### bridge - skip link-local and broadcast address
ebtables -t broute -A V2RAY_BRIDGE --mark 0x70/0x70 -j RETURN

ebtables -t broute -A V2RAY_BRIDGE -p ipv4 --ip-dst 127.0.0.1/32 -j RETURN
ebtables -t broute -A V2RAY_BRIDGE -p ipv4 --ip-dst 224.0.0.0/4 -j RETURN
ebtables -t broute -A V2RAY_BRIDGE -p ipv4 --ip-dst 255.255.255.255/32 -j RETURN
if [[ $TPROXY_SETUP_WITHOUT_IPV6 -eq 0 ]]; then
  for LOCAL_IPV6 in ${ROUTER_LOCAL_NET_IPV6[@]}; do
    ebtables -t broute -A V2RAY_BRIDGE -p ipv6 --ip6-dst "$LOCAL_IPV6" -j RETURN
  done
  ebtables -t broute -A V2RAY_BRIDGE -p ipv6 --ip6-dst ff00::/8 -j RETURN
fi

### bridge - skip private network and UDP of DNS
for LOCAL_IPV4 in ${ROUTER_LOCAL_NET_IPV4[@]}; do
  ebtables -t broute -A V2RAY_BRIDGE -p ipv4 --ip-dst "$LOCAL_IPV4" -j RETURN
done

### bridge - skip CN DNS
# ebtables -t broute -A V2RAY_BRIDGE -p ipv4 --ip-dst 119.29.29.29/32 -j RETURN
# ebtables -t broute -A V2RAY_BRIDGE -p ipv4 --ip-dst 223.5.5.5/32 -j RETURN
# ebtables -t broute -A V2RAY_BRIDGE -p ipv4 --ip-dst 223.6.6.6/32 -j RETURN
# ebtables -t broute -A V2RAY_BRIDGE -p ipv4 --ip-dst 180.76.76.76/32 -j RETURN
# ebtables -t broute -A V2RAY_BRIDGE -p ipv4 --ip-dst 1.12.12.12/32 -j RETURN
# ebtables -t broute -A V2RAY_BRIDGE -p ipv4 --ip-dst 120.53.53.53/32 -j RETURN
# ebtables -t broute -A V2RAY_BRIDGE -p ipv4 --ip-dst 1.1.1.1/32 -j RETURN
# ebtables -t broute -A V2RAY_BRIDGE -p ipv4 --ip-dst 1.0.0.1/32 -j RETURN
# if [[ $TPROXY_SETUP_WITHOUT_IPV6 -eq 0 ]]; then
#   ebtables -t broute -A V2RAY_BRIDGE -p ipv6 --ip6-dst 2400:3200::1/128 -j RETURN
#   ebtables -t broute -A V2RAY_BRIDGE -p ipv6 --ip6-dst 2400:3200:baba::1/128 -j RETURN
#   ebtables -t broute -A V2RAY_BRIDGE -p ipv6 --ip6-dst 2400:da00::6666/128 -j RETURN
#   ebtables -t broute -A V2RAY_BRIDGE -p ipv6 --ip6-dst 2402:4e00::/128 -j RETURN
#   ebtables -t broute -A V2RAY_BRIDGE -p ipv6 --ip6-dst 2606:4700:4700::1111/128 -j RETURN
#   ebtables -t broute -A V2RAY_BRIDGE -p ipv6 --ip6-dst 2606:4700:4700::1001/128 -j RETURN
# fi
ebtables -t broute -A V2RAY_BRIDGE -p ipv4 --ip-proto udp --ip-dport 53 -j RETURN
ebtables -t broute -A V2RAY_BRIDGE -p ipv4 --ip-proto tcp --ip-dport 53 -j RETURN
ebtables -t broute -A V2RAY_BRIDGE -p ipv4 --ip-proto udp --ip-dport 853 -j RETURN
ebtables -t broute -A V2RAY_BRIDGE -p ipv4 --ip-proto tcp --ip-dport 853 -j RETURN
if [[ $TPROXY_SETUP_WITHOUT_IPV6 -eq 0 ]]; then
  ebtables -t broute -A V2RAY_BRIDGE -p ipv6 --ip6-proto udp --ip6-dport 53 -j RETURN
  ebtables -t broute -A V2RAY_BRIDGE -p ipv6 --ip6-proto tcp --ip6-dport 53 -j RETURN
  ebtables -t broute -A V2RAY_BRIDGE -p ipv6 --ip6-proto udp --ip6-dport 853 -j RETURN
  ebtables -t broute -A V2RAY_BRIDGE -p ipv6 --ip6-proto tcp --ip6-dport 853 -j RETURN
fi

if [[ $SETUP_WITH_DEBUG_LOG -ne 0 ]]; then
  ebtables -t broute -A V2RAY_BRIDGE --log-ip --log-level debug --log-prefix "---BRIDGE-DROP: "
fi

### ipv4 - forward to v2ray's listen address if not marked by v2ray
# tproxy ip to $V2RAY_HOST_IPV4:$V2RAY_PORT
ebtables -t broute -A V2RAY_BRIDGE -j redirect --redirect-target DROP

# reset chain
ebtables -t broute -D BROUTING -p ipv4 --ip-proto tcp -j V2RAY_BRIDGE >/dev/null 2>&1
while [[ $? -eq 0 ]]; do
  ebtables -t broute -D BROUTING -p ipv4 --ip-proto tcp -j V2RAY_BRIDGE >/dev/null 2>&1
done
ebtables -t broute -D BROUTING -p ipv4 --ip-proto udp -j V2RAY_BRIDGE >/dev/null 2>&1
while [[ $? -eq 0 ]]; do
  ebtables -t broute -D BROUTING -p ipv4 --ip-proto udp -j V2RAY_BRIDGE >/dev/null 2>&1
done

ebtables -t broute -A BROUTING -p ipv4 --ip-proto tcp -j V2RAY_BRIDGE
ebtables -t broute -A BROUTING -p ipv4 --ip-proto udp -j V2RAY_BRIDGE

ebtables -t broute -D BROUTING -p ipv6 --ip6-proto tcp -j V2RAY_BRIDGE >/dev/null 2>&1
while [[ $? -eq 0 ]]; do
  ebtables -t broute -D BROUTING -p ipv6 --ip6-proto tcp -j V2RAY_BRIDGE >/dev/null 2>&1
done
ebtables -t broute -D BROUTING -p ipv6 --ip6-proto udp -j V2RAY_BRIDGE >/dev/null 2>&1
while [[ $? -eq 0 ]]; do
  ebtables -t broute -D BROUTING -p ipv6 --ip6-proto udp -j V2RAY_BRIDGE >/dev/null 2>&1
done

if [[ $TPROXY_SETUP_WITHOUT_IPV6 -eq 0 ]]; then
  ebtables -t broute -A BROUTING -p ipv6 --ip6-proto tcp -j V2RAY_BRIDGE
  ebtables -t broute -A BROUTING -p ipv6 --ip6-proto udp -j V2RAY_BRIDGE
fi
