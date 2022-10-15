#!/bin/bash

# nftables
# Quick: https://wiki.nftables.org/wiki-nftables/index.php/Performing_Network_Address_Translation_(NAT)
# Quick(CN): https://wiki.archlinux.org/index.php/Nftables_(%E7%AE%80%E4%BD%93%E4%B8%AD%E6%96%87)#Masquerading
# List all tables/chains/rules/matches/statements: https://wiki.nftables.org/wiki-nftables/index.php/Quick_reference-nftables_in_10_minutes#Rules
# man 8 nft:
#    https://www.netfilter.org/projects/nftables/manpage.html
#    https://www.mankier.com/8/nft
# IP http://ftp.apnic.net/apnic/stats/apnic/delegated-apnic-latest
#    ipv4 <start> <count> => ipv4 58.42.0.0 65536
#    ipv6 <prefix> <bits> => ipv6 2407:c380:: 32
# Netfilter: https://en.wikipedia.org/wiki/Netfilter
#            http://inai.de/images/nf-packet-flow.svg
# Policy Routing: See RPDB in https://www.man7.org/linux/man-pages/man8/ip-rule.8.html
# Monitor: nft monitor

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
source "$(dirname "$SCRIPT_DIR")/configure-router.sh"

### ==================================== v2ray nftables rules begin ====================================
### ----------------------------------- $ROUTER_HOME/v2ray/setup-tproxy.sh -----------------------------------

### Setup v2ray xtable rule and policy routing
### ip rule { add | del } SELECTOR ACTION
### default table/rule-> local(ID: 255)/Priority: 0 , main(ID: 254)/Priority: 32766 , default(ID: 253)/Priority: 32766
### 策略路由(占用mark的后8位,RPDB变化均会触发重路由):
###   OUTPUT 链约定    : 判定需要重路由设置 设置 fwmark = 0x0e/0x0f (00001110)
###   PREROUTING链约定 : 跳过tproxy fwmark = 0x70/0x70 (01110000)
###   所有 fwmark = 0x0e/0x0f 的包走 table 100
###     (v2ray会设置255,0xff), 避开 0x0e/0x0f 规则(跳过table 100)，满足 0x70/0x70 规则(防止循环重定向)

if [[ "x" == "x$V2RAY_HOST_IPV4" ]]; then
  V2RAY_HOST_IPV4=
fi

if [[ "x" == "x$V2RAY_PORT" ]]; then
  V2RAY_PORT=3371
fi

if [[ "x" == "x$SETUP_FWMARK_RULE_PRIORITY" ]]; then
  SETUP_FWMARK_RULE_PRIORITY=17995
fi

if [[ "x" == "x$SETUP_WITH_BLACKLIST_IPV4" ]]; then
  SETUP_WITH_BLACKLIST_IPV4="119.29.29.29,223.5.5.5,223.6.6.6,180.76.76.76,119.28.22.204,119.28.142.155,43.132.185.197,1.12.12.12,120.53.53.53,1.1.1.1,1.0.0.1"
fi
if [[ "x" == "x$SETUP_WITH_BLACKLIST_IPV6" ]]; then
  SETUP_WITH_BLACKLIST_IPV6="2402:4e00::,2400:3200::1,2400:3200:baba::1,2400:da00::6666,2402:4e00::,2606:4700:4700::1111,2606:4700:4700::1001,2606:4700:4700::1111,2606:4700:4700::1001"
fi

if [[ "x" == "x$SETUP_WITH_DEBUG_LOG" ]]; then
  SETUP_WITH_DEBUG_LOG=0
fi

if [[ $(ip -4 route list 0.0.0.0/0 dev lo table 100 | wc -l) -eq 0 ]]; then
  ip -4 route add local 0.0.0.0/0 dev lo table 100
fi

FWMARK_LOOPUP_TABLE_100=$(ip -4 rule show fwmark 0x0e/0x0f lookup 100 | awk 'END {print NF}')
while [[ 0 -ne $FWMARK_LOOPUP_TABLE_100 ]]; do
  ip -4 rule delete fwmark 0x0e/0x0f lookup 100
  FWMARK_LOOPUP_TABLE_100=$(ip -4 rule show fwmark 0x0e/0x0f lookup 100 | awk 'END {print NF}')
done
SETUP_FWMARK_RULE_RETRY_TIMES=0
ip -4 rule add fwmark 0x0e/0x0f priority $SETUP_FWMARK_RULE_PRIORITY lookup 100
while [[ $? -ne 0 ]] && [[ $SETUP_FWMARK_RULE_RETRY_TIMES -lt 1000 ]]; do
  let SETUP_FWMARK_RULE_RETRY_TIMES=$SETUP_FWMARK_RULE_RETRY_TIMES+1
  let SETUP_FWMARK_RULE_PRIORITY=$SETUP_FWMARK_RULE_PRIORITY-1
  ip -4 rule add fwmark 0x0e/0x0f priority $SETUP_FWMARK_RULE_PRIORITY lookup 100
done

if [[ $TPROXY_SETUP_WITHOUT_IPV6 -eq 0 ]]; then
  if [[ $(ip -6 route list ::/0 dev lo table 100 | wc -l) -eq 0 ]]; then
    ip -6 route add local ::/0 dev lo table 100
  fi
  FWMARK_LOOPUP_TABLE_100=$(ip -6 rule show fwmark 0x0e/0x0f lookup 100 | awk 'END {print NF}')
  while [[ 0 -ne $FWMARK_LOOPUP_TABLE_100 ]]; do
    ip -6 rule delete fwmark 0x0e/0x0f lookup 100
    FWMARK_LOOPUP_TABLE_100=$(ip -6 rule show fwmark 0x0e/0x0f lookup 100 | awk 'END {print NF}')
  done
  SETUP_FWMARK_RULE_RETRY_TIMES=0
  ip -6 rule add fwmark 0x0e/0x0f priority $SETUP_FWMARK_RULE_PRIORITY lookup 100
  while [[ $? -ne 0 ]] && [[ $SETUP_FWMARK_RULE_RETRY_TIMES -lt 1000 ]]; do
    let SETUP_FWMARK_RULE_RETRY_TIMES=$SETUP_FWMARK_RULE_RETRY_TIMES+1
    let SETUP_FWMARK_RULE_PRIORITY=$SETUP_FWMARK_RULE_PRIORITY-1
    ip -6 rule add fwmark 0x0e/0x0f priority $SETUP_FWMARK_RULE_PRIORITY lookup 100
  done
else
  FWMARK_LOOPUP_TABLE_100=$(ip -6 rule show fwmark 0x0e/0x0f lookup 100 | awk 'END {print NF}')
  while [[ 0 -ne $FWMARK_LOOPUP_TABLE_100 ]]; do
    ip -6 rule delete fwmark 0x0e/0x0f lookup 100
    FWMARK_LOOPUP_TABLE_100=$(ip -6 rule show fwmark 0x0e/0x0f lookup 100 | awk 'END {print NF}')
  done
  ip -6 route del local ::/0 dev lo table 100 >/dev/null 2>&1
fi
# ip route show table 100

nft list table ip v2ray >/dev/null 2>&1
if [[ $? -ne 0 ]]; then
  nft add table ip v2ray
fi

if [[ $TPROXY_SETUP_WITHOUT_IPV6 -eq 0 ]]; then
  nft list table ip6 v2ray >/dev/null 2>&1
  if [ $? -ne 0 ]; then
    nft add table ip6 v2ray
  fi
fi

nft list table bridge v2ray >/dev/null 2>&1
if [[ $? -ne 0 ]]; then
  nft add table bridge v2ray
fi

### See https://toutyrater.github.io/app/tproxy.html

### Setup - ipv4
nft list set ip v2ray BLACKLIST >/dev/null 2>&1
if [[ $? -ne 0 ]]; then
  nft add set ip v2ray BLACKLIST { type ipv4_addr\; }
fi
nft add element ip v2ray BLACKLIST "{ $SETUP_WITH_BLACKLIST_IPV4 }"
nft list set ip v2ray TEMPORARY_WHITELIST >/dev/null 2>&1
if [[ $? -ne 0 ]]; then
  nft add set ip v2ray TEMPORARY_WHITELIST '{ type ipv4_addr; timeout 2d; }'
fi
nft list set ip v2ray PERMANENT_WHITELIST >/dev/null 2>&1
if [[ $? -ne 0 ]]; then
  nft add set ip v2ray PERMANENT_WHITELIST '{ type ipv4_addr; flags interval; auto-merge; }'
fi
if [ ${#TPROXY_WHITELIST_IPV4[@]} -gt 0 ]; then
  nft add element ip v2ray PERMANENT_WHITELIST "{$(echo "${TPROXY_WHITELIST_IPV4[@]}" | sed -E 's;[[:space:]]+;,;g')}"
fi

if [ $TPROXY_SETUP_USING_GEOIP -ne 0 ]; then
  nft list set ip v2ray GEOIP_CN >/dev/null 2>&1
  if [[ $? -ne 0 ]]; then
    nft add set ip v2ray GEOIP_CN '{ type ipv4_addr; flags interval; }'
  fi
  nft list set ip v2ray GEOIP_HK >/dev/null 2>&1
  if [[ $? -ne 0 ]]; then
    nft add set ip v2ray GEOIP_HK '{ type ipv4_addr; flags interval; }'
  fi
fi
nft list set ip v2ray LOCAL_IPV4 >/dev/null 2>&1
if [[ $? -ne 0 ]]; then
  nft add set ip v2ray LOCAL_IPV4 '{ type ipv4_addr; flags interval; auto-merge ; }'
  nft add element ip v2ray LOCAL_IPV4 '{127.0.0.1/32, 169.254.0.0/16, 192.168.0.0/16, 172.16.0.0/12, 10.0.0.0/8}'
fi
nft list set ip v2ray DEFAULT_ROUTE_IPV4 >/dev/null 2>&1
if [[ $? -ne 0 ]]; then
  nft add set ip v2ray DEFAULT_ROUTE_IPV4 '{ type ipv4_addr; flags interval; auto-merge ; }'
fi
nft list set ip v2ray PROXY_DNS_IPV4 >/dev/null 2>&1
if [[ $? -ne 0 ]]; then
  nft add set ip v2ray PROXY_DNS_IPV4 '{ type ipv4_addr; }'
  nft add element ip v2ray PROXY_DNS_IPV4 '{8.8.8.8, 8.8.4.4}'
fi

nft list chain ip v2ray PREROUTING >/dev/null 2>&1
if [[ $? -ne 0 ]]; then
  nft add chain ip v2ray PREROUTING { type filter hook prerouting priority filter + 1 \; }
fi
nft flush chain ip v2ray PREROUTING

### ipv4 - skip internal services
nft add rule ip v2ray PREROUTING meta l4proto != {tcp, udp} return
# DNAT or connect from outside
nft add rule ip v2ray PREROUTING tcp sport "{$ROUTER_INTERNAL_SERVICE_PORT_TCP}" return
nft add rule ip v2ray PREROUTING udp sport "{$ROUTER_INTERNAL_SERVICE_PORT_UDP}" return
nft add rule ip v2ray PREROUTING udp dport "{$ROUTER_INTERNAL_DIRECTLY_VISIT_UDP_DPORT}" return
nft add rule ip v2ray PREROUTING ip daddr != @PROXY_DNS_IPV4 udp dport '{53, 853}' return
nft add rule ip v2ray PREROUTING ip daddr != @PROXY_DNS_IPV4 tcp dport '{53, 853}' return

### ipv4 - skip link-local and broadcast address, 172.20.1.1/24 is used for remote debug
nft add rule ip v2ray PREROUTING ip daddr {224.0.0.0/4, 255.255.255.255/32, 172.20.1.1/24} return
### ipv4 - skip private network and UDP of DNS
nft add rule ip v2ray PREROUTING ip daddr @LOCAL_IPV4 return
nft add rule ip v2ray PREROUTING ip daddr @DEFAULT_ROUTE_IPV4 return
# if dns service and V2RAY are on different server, use rules below
# nft add rule ip v2ray PREROUTING meta l4proto tcp ip daddr @LOCAL_IPV4 return
# nft add rule ip v2ray PREROUTING meta l4proto tcp ip daddr @DEFAULT_ROUTE_IPV4 return
# nft add rule ip v2ray PREROUTING ip daddr @LOCAL_IPV4 udp dport != 53 return
# nft add rule ip v2ray PREROUTING ip daddr @DEFAULT_ROUTE_IPV4 udp dport != 53 return
nft add rule ip v2ray PREROUTING mark and 0x70 == 0x70 return

# ipv4 skip package from outside
nft add rule ip v2ray PREROUTING ip daddr @BLACKLIST return
if [ $TPROXY_SETUP_USING_GEOIP -ne 0 ]; then
  # GEOIP_CN
  nft add rule ip v2ray PREROUTING ip daddr @GEOIP_CN return
## GEOIP_HK
#nft add rule ip v2ray PREROUTING ip daddr @GEOIP_HK return
else
  ## Alternative: using whitlist
  nft add rule ip v2ray PREROUTING ip daddr != @TEMPORARY_WHITELIST ip daddr != @PERMANENT_WHITELIST return
fi

### ipv4 - forward to v2ray's listen address if not marked by v2ray
# tproxy ip to $V2RAY_HOST_IPV4:$V2RAY_PORT
if [[ $SETUP_WITH_DEBUG_LOG -ne 0 ]]; then
  nft add rule ip v2ray PREROUTING meta nftrace set 1
  nft add rule ip v2ray PREROUTING log prefix '">>>TCP4>tproxy:"' level debug flags all
fi

# fwmark here must match: ip rule list lookup 100
nft add rule ip v2ray PREROUTING mark and 0x7f != 0x7e meta mark set mark and 0xffffff80 xor 0x7e
nft add rule ip v2ray PREROUTING ct mark set mark and 0xffff
nft add rule ip v2ray PREROUTING meta l4proto tcp tproxy to :$V2RAY_PORT accept # -j TPROXY --on-port $V2RAY_PORT --tproxy-mark 0x7e/0x7f # mark tcp package with 1 and forward to $V2RAY_PORT
nft add rule ip v2ray PREROUTING meta l4proto udp tproxy to :$V2RAY_PORT accept # -j TPROXY --on-port $V2RAY_PORT --tproxy-mark 0x7e/0x7f # mark tcp package with 1 and forward to $V2RAY_PORT

# Setup - ipv4 local
nft list chain ip v2ray OUTPUT >/dev/null 2>&1
if [[ $? -ne 0 ]]; then
  nft add chain ip v2ray OUTPUT { type route hook output priority filter + 1 \; }
fi
nft flush chain ip v2ray OUTPUT

### ipv4 - skip internal services
nft add rule ip v2ray OUTPUT meta l4proto != {tcp, udp} return
nft add rule ip v2ray OUTPUT tcp sport "{$ROUTER_INTERNAL_SERVICE_PORT_TCP}" return
nft add rule ip v2ray OUTPUT udp sport "{$ROUTER_INTERNAL_SERVICE_PORT_UDP}" return
nft add rule ip v2ray OUTPUT udp dport "{$ROUTER_INTERNAL_DIRECTLY_VISIT_UDP_DPORT}" return
nft add rule ip v2ray OUTPUT ip daddr != @PROXY_DNS_IPV4 udp dport '{53, 853}' return
nft add rule ip v2ray OUTPUT ip daddr != @PROXY_DNS_IPV4 tcp dport '{53, 853}' return

# 172.20.1.1/24 is used for remote debug
nft add rule ip v2ray OUTPUT ip daddr {224.0.0.0/4, 255.255.255.255/32, 172.20.1.1/24} return
nft add rule ip v2ray OUTPUT ip daddr @LOCAL_IPV4 return
nft add rule ip v2ray OUTPUT ip daddr @DEFAULT_ROUTE_IPV4 return
nft add rule ip v2ray OUTPUT ip daddr @BLACKLIST return
if [ $TPROXY_SETUP_USING_GEOIP -ne 0 ]; then
  nft add rule ip v2ray OUTPUT ip daddr @GEOIP_CN return
else
  ## Alternative: using whitlist
  nft add rule ip v2ray OUTPUT ip daddr != @TEMPORARY_WHITELIST ip daddr != @PERMANENT_WHITELIST return
fi
# if dns service and v2ray are on different server, use rules below
# nft add rule ip v2ray OUTPUT meta l4proto tcp ip daddr @LOCAL_IPV4 return
# nft add rule ip v2ray OUTPUT meta l4proto tcp ip daddr @DEFAULT_ROUTE_IPV4 return
# nft add rule ip v2ray OUTPUT ip daddr @LOCAL_IPV4 udp dport != 53 return
# nft add rule ip v2ray OUTPUT ip daddr @DEFAULT_ROUTE_IPV4 udp dport != 53 return
nft add rule ip v2ray OUTPUT mark and 0x70 == 0x70 return
if [[ $SETUP_WITH_DEBUG_LOG -ne 0 ]]; then
  nft add rule ip v2ray OUTPUT meta nftrace set 1
  nft add rule ip v2ray OUTPUT log prefix '"+++TCP4+mark 1:"' level debug flags all
fi
nft add rule ip v2ray OUTPUT mark and 0x0f != 0x0e meta l4proto {tcp, udp} mark set mark and 0xfffffff0 xor 0x0e return
nft add rule ip v2ray OUTPUT ct mark set mark and 0xffff

## Setup - ipv6
if [[ $TPROXY_SETUP_WITHOUT_IPV6 -eq 0 ]]; then
  nft list set ip6 v2ray BLACKLIST >/dev/null 2>&1
  if [[ $? -ne 0 ]]; then
    nft add set ip6 v2ray BLACKLIST '{ type ipv6_addr; }'
  fi
  nft add element ip6 v2ray BLACKLIST "{ $SETUP_WITH_BLACKLIST_IPV6 }"
  nft list set ip6 v2ray TEMPORARY_WHITELIST >/dev/null 2>&1
  if [[ $? -ne 0 ]]; then
    nft add set ip6 v2ray TEMPORARY_WHITELIST '{ type ipv6_addr; timeout 2d; }'
  fi
  nft list set ip6 v2ray PERMANENT_WHITELIST >/dev/null 2>&1
  if [[ $? -ne 0 ]]; then
    nft add set ip6 v2ray PERMANENT_WHITELIST '{ type ipv6_addr; flags interval; auto-merge; }'
  fi
  if [ ${#TPROXY_WHITELIST_IPV6[@]} -gt 0 ]; then
    nft add element ip6 v2ray PERMANENT_WHITELIST "{$(echo "${TPROXY_WHITELIST_IPV6[@]}" | sed -E 's;[[:space:]]+;,;g')}"
  fi
  if [ $TPROXY_SETUP_USING_GEOIP -ne 0 ]; then
    nft list set ip6 v2ray GEOIP_CN >/dev/null 2>&1
    if [[ $? -ne 0 ]]; then
      nft add set ip6 v2ray GEOIP_CN '{ type ipv6_addr; flags interval; }'
    fi
    nft list set ip6 v2ray GEOIP_HK >/dev/null 2>&1
    if [[ $? -ne 0 ]]; then
      nft add set ip6 v2ray GEOIP_HK '{ type ipv6_addr; flags interval; }'
    fi
  fi
  nft list set ip6 v2ray LOCAL_IPV6 >/dev/null 2>&1
  if [[ $? -ne 0 ]]; then
    nft add set ip6 v2ray LOCAL_IPV6 '{ type ipv6_addr; flags interval; auto-merge ; }'
    nft add element ip6 v2ray LOCAL_IPV6 '{::1/128, fc00::/7, fe80::/10}'
  fi
  nft list set ip6 v2ray DEFAULT_ROUTE_IPV6 >/dev/null 2>&1
  if [[ $? -ne 0 ]]; then
    nft add set ip6 v2ray DEFAULT_ROUTE_IPV6 '{ type ipv6_addr; flags interval; auto-merge ; }'
  fi
  nft list set ip6 v2ray PROXY_DNS_IPV6 >/dev/null 2>&1
  if [[ $? -ne 0 ]]; then
    nft add set ip6 v2ray PROXY_DNS_IPV6 '{ type ipv6_addr; }'
    nft add element ip6 v2ray PROXY_DNS_IPV6 '{2001:4860:4860::8888, 2001:4860:4860::8844}'
  fi

  nft list chain ip6 v2ray PREROUTING >/dev/null 2>&1
  if [[ $? -ne 0 ]]; then
    nft add chain ip6 v2ray PREROUTING { type filter hook prerouting priority filter + 1 \; }
  fi
  nft flush chain ip6 v2ray PREROUTING

  ### ipv6 - skip internal services
  nft add rule ip6 v2ray PREROUTING meta l4proto != {tcp, udp} return
  nft add rule ip6 v2ray PREROUTING tcp sport "{$ROUTER_INTERNAL_SERVICE_PORT_TCP}" return
  nft add rule ip6 v2ray PREROUTING udp sport "{$ROUTER_INTERNAL_SERVICE_PORT_UDP}" return
  nft add rule ip6 v2ray PREROUTING udp dport "{$ROUTER_INTERNAL_DIRECTLY_VISIT_UDP_DPORT}" return
  nft add rule ip6 v2ray PREROUTING ip6 daddr != @PROXY_DNS_IPV6 udp dport '{53, 853}' return
  nft add rule ip6 v2ray PREROUTING ip6 daddr != @PROXY_DNS_IPV6 tcp dport '{53, 853}' return
  nft add rule ip6 v2ray PREROUTING mark and 0x70 == 0x70 return

  ### ipv6 - skip multicast
  nft add rule ip6 v2ray PREROUTING ip6 daddr '{ ff00::/8 }' return
  ### ipv6 - skip link/unique-local fc00::/7,fe80::/10 and ::1/128 are in ip -6 address show scope host/link
  nft add rule ip6 v2ray PREROUTING ip6 daddr @LOCAL_IPV6 return
  nft add rule ip6 v2ray PREROUTING ip6 daddr @DEFAULT_ROUTE_IPV6 return

  ### ipv6 - skip private network and UDP of DNS
  # ipv6 skip package from outside
  nft add rule ip6 v2ray PREROUTING ip6 daddr @BLACKLIST return
  if [ $TPROXY_SETUP_USING_GEOIP -ne 0 ]; then
    # GEOIP_CN
    nft add rule ip6 v2ray PREROUTING ip6 daddr @GEOIP_CN return
    ## GEOIP_HK
    #nft add rule ip6 v2ray PREROUTING ip6 daddr @GEOIP_HK return
  else
    ## Alternative: using whitlist
    nft add rule ip6 v2ray PREROUTING ip6 daddr != @TEMPORARY_WHITELIST ip6 daddr != @PERMANENT_WHITELIST return
  fi

  ### ipv6 - forward to v2ray's listen address if not marked by v2ray
  if [[ $SETUP_WITH_DEBUG_LOG -ne 0 ]]; then
    nft add rule ip6 v2ray PREROUTING meta nftrace set 1
    nft add rule ip6 v2ray PREROUTING log prefix '">>>TCP6>tproxy:"' level debug flags all
  fi
  # tproxy ip6 to $V2RAY_HOST_IPV6:$V2RAY_PORT
  # fwmark here must match: ip -6 rule list lookup 100
  nft add rule ip6 v2ray PREROUTING mark and 0x7f != 0x7e meta mark set mark and 0xffffff80 xor 0x7e
  nft add rule ip6 v2ray PREROUTING ct mark set mark and 0xffff
  nft add rule ip6 v2ray PREROUTING meta l4proto tcp tproxy to :$V2RAY_PORT accept # -j TPROXY --on-port $V2RAY_PORT --tproxy-mark 0x7e/0x7f  # mark tcp package with 1 and forward to $V2RAY_PORT
  nft add rule ip6 v2ray PREROUTING meta l4proto udp tproxy to :$V2RAY_PORT accept # -j TPROXY --on-port $V2RAY_PORT --tproxy-mark 0x7e/0x7f  # mark tcp package with 1 and forward to $V2RAY_PORT

  # Setup - ipv6 local
  nft list chain ip6 v2ray OUTPUT >/dev/null 2>&1
  if [[ $? -ne 0 ]]; then
    nft add chain ip6 v2ray OUTPUT { type route hook output priority filter + 1 \; }
  fi
  nft flush chain ip6 v2ray OUTPUT

  ### ipv6 - skip internal services
  nft add rule ip6 v2ray OUTPUT meta l4proto != {tcp, udp} return
  nft add rule ip6 v2ray OUTPUT tcp sport "{$ROUTER_INTERNAL_SERVICE_PORT_TCP}" return
  nft add rule ip6 v2ray OUTPUT udp sport "{$ROUTER_INTERNAL_SERVICE_PORT_UDP}" return
  nft add rule ip6 v2ray OUTPUT udp dport "{$ROUTER_INTERNAL_DIRECTLY_VISIT_UDP_DPORT}" return
  nft add rule ip6 v2ray OUTPUT ip6 daddr != @PROXY_DNS_IPV6 udp dport '{53, 853}' return
  nft add rule ip6 v2ray OUTPUT ip6 daddr != @PROXY_DNS_IPV6 tcp dport '{53, 853}' return

  ### ipv6 - skip multicast
  nft add rule ip6 v2ray OUTPUT ip6 daddr '{ ff00::/8 }' return
  ### ipv6 - skip link/unique-local fc00::/7,fe80::/10 and  ::1/128 are in ip -6 address show scope host/link
  nft add rule ip6 v2ray OUTPUT ip6 daddr @LOCAL_IPV6 return
  nft add rule ip6 v2ray OUTPUT ip6 daddr @DEFAULT_ROUTE_IPV6 return
  nft add rule ip6 v2ray OUTPUT ip6 daddr @BLACKLIST return
  if [ $TPROXY_SETUP_USING_GEOIP -ne 0 ]; then
    ## GEOIP_CN
    nft add rule ip6 v2ray OUTPUT ip6 daddr @GEOIP_CN return
    ## GEOIP_HK
    #nft add rule ip6 v2ray OUTPUT ip6 daddr @GEOIP_HK return
  else
    ## Alternative: using whitlist
    nft add rule ip6 v2ray PREROUTING ip6 daddr != @TEMPORARY_WHITELIST ip6 daddr != @PERMANENT_WHITELIST return
  fi
  nft add rule ip6 v2ray OUTPUT mark and 0x70 == 0x70 return # make sure v2ray's outbounds.*.streamSettings.sockopt.mark = 255
  if [[ $SETUP_WITH_DEBUG_LOG -ne 0 ]]; then
    nft add rule ip6 v2ray OUTPUT meta nftrace set 1
    nft add rule ip6 v2ray OUTPUT log prefix '"+++TCP6+mark 1:"' level debug flags all
  fi
  nft add rule ip6 v2ray OUTPUT mark and 0x0f != 0x0e meta l4proto {tcp, udp} mark set mark and 0xfffffff0 xor 0x0e return
  nft add rule ip6 v2ray OUTPUT ct mark set mark and 0xffff
else
  nft delete chain ip6 v2ray PREROUTING >/dev/null 2>&1
  nft delete chain ip6 v2ray OUTPUT >/dev/null 2>&1
fi

### Setup - bridge
nft list set bridge v2ray LOCAL_IPV4 >/dev/null 2>&1
if [ $? -ne 0 ]; then
  nft add set bridge v2ray LOCAL_IPV4 '{ type ipv4_addr; flags interval; auto-merge ; }'
  nft add element bridge v2ray LOCAL_IPV4 '{127.0.0.1/32, 169.254.0.0/16, 192.168.0.0/16, 172.16.0.0/12, 10.0.0.0/8}'
fi
nft list set bridge v2ray DEFAULT_ROUTE_IPV4 >/dev/null 2>&1
if [ $? -ne 0 ]; then
  nft add set bridge v2ray DEFAULT_ROUTE_IPV4 '{ type ipv4_addr; flags interval; auto-merge; }'
fi
nft list set bridge v2ray PROXY_DNS_IPV4 >/dev/null 2>&1
if [ $? -ne 0 ]; then
  nft add set bridge v2ray PROXY_DNS_IPV4 '{ type ipv4_addr; }'
  nft add element bridge v2ray PROXY_DNS_IPV4 '{8.8.8.8, 8.8.4.4}'
fi
nft list set bridge v2ray TEMPORARY_WHITELIST_IPV4 >/dev/null 2>&1
if [[ $? -ne 0 ]]; then
  nft add set bridge v2ray TEMPORARY_WHITELIST_IPV4 '{ type ipv4_addr; timeout 2d; }'
fi
nft list set bridge v2ray PERMANENT_WHITELIST_IPV4 >/dev/null 2>&1
if [[ $? -ne 0 ]]; then
  nft add set bridge v2ray PERMANENT_WHITELIST_IPV4 '{ type ipv4_addr; flags interval; auto-merge; }'
fi
if [ ${#TPROXY_WHITELIST_IPV4[@]} -gt 0 ]; then
  nft add element bridge v2ray PERMANENT_WHITELIST_IPV4 "{$(echo "${TPROXY_WHITELIST_IPV4[@]}" | sed -E 's;[[:space:]]+;,;g')}"
fi

nft list set bridge v2ray LOCAL_IPV6 >/dev/null 2>&1
if [ $? -ne 0 ]; then
  nft add set bridge v2ray LOCAL_IPV6 '{ type ipv6_addr; flags interval; auto-merge; }'
  nft add element bridge v2ray LOCAL_IPV6 '{::1/128, fc00::/7, fe80::/10}'
fi
nft list set bridge v2ray DEFAULT_ROUTE_IPV6 >/dev/null 2>&1
if [ $? -ne 0 ]; then
  nft add set bridge v2ray DEFAULT_ROUTE_IPV6 '{ type ipv6_addr; flags interval; auto-merge ; }'
fi
nft list set bridge v2ray PROXY_DNS_IPV6 >/dev/null 2>&1
if [ $? -ne 0 ]; then
  nft add set bridge v2ray PROXY_DNS_IPV6 '{ type ipv6_addr; }'
  nft add element bridge v2ray PROXY_DNS_IPV6 '{2001:4860:4860::8888, 2001:4860:4860::8844}'
fi
nft list set bridge v2ray TEMPORARY_WHITELIST_IPV6 >/dev/null 2>&1
if [[ $? -ne 0 ]]; then
  nft add set bridge v2ray TEMPORARY_WHITELIST_IPV6 '{ type ipv6_addr; timeout 2d; }'
fi
nft list set bridge v2ray PERMANENT_WHITELIST_IPV6 >/dev/null 2>&1
if [[ $? -ne 0 ]]; then
  nft add set bridge v2ray PERMANENT_WHITELIST_IPV6 '{ type ipv6_addr; flags interval; auto-merge; }'
fi
if [ ${#TPROXY_WHITELIST_IPV6[@]} -gt 0 ]; then
  nft add element bridge v2ray PERMANENT_WHITELIST_IPV6 "{$(echo "${TPROXY_WHITELIST_IPV6[@]}" | sed -E 's;[[:space:]]+;,;g')}"
fi

nft list chain bridge v2ray PREROUTING >/dev/null 2>&1
if [[ $? -ne 0 ]]; then
  nft add chain bridge v2ray PREROUTING { type filter hook prerouting priority -280 \; }
fi
nft flush chain bridge v2ray PREROUTING

### bridge - skip internal services
nft add rule bridge v2ray PREROUTING meta l4proto != {tcp, udp} return
# nft add rule bridge v2ray PREROUTING tcp sport "{$ROUTER_INTERNAL_SERVICE_PORT_TCP}" return
# nft add rule bridge v2ray PREROUTING udp sport "{$ROUTER_INTERNAL_SERVICE_PORT_UDP}" return
nft add rule bridge v2ray PREROUTING udp dport "{$ROUTER_INTERNAL_DIRECTLY_VISIT_UDP_DPORT}" return
nft add rule bridge v2ray PREROUTING ip daddr != @PROXY_DNS_IPV4 udp dport '{53, 853}' return
nft add rule bridge v2ray PREROUTING ip daddr != @PROXY_DNS_IPV4 tcp dport '{53, 853}' return
nft add rule bridge v2ray PREROUTING ip6 daddr != @PROXY_DNS_IPV6 udp dport '{53, 853}' return
nft add rule bridge v2ray PREROUTING ip6 daddr != @PROXY_DNS_IPV6 tcp dport '{53, 853}' return

### bridge - skip link-local and broadcast address
nft add rule bridge v2ray PREROUTING mark and 0x70 == 0x70 return

### bridge - skip private network and UDP of DNS, 172.20.1.1/24 is used for remote debug
nft add rule bridge v2ray PREROUTING ip saddr @LOCAL_IPV4 pkttype '{broadcast, multicast}' accept
nft add rule bridge v2ray PREROUTING ip daddr {224.0.0.0/4, 255.255.255.255/32, 172.20.1.1/24} return
nft add rule bridge v2ray PREROUTING ip daddr @LOCAL_IPV4 return
nft add rule bridge v2ray PREROUTING ip daddr @DEFAULT_ROUTE_IPV4 return
# if dns service and V2RAY are on different server, use rules below
# nft add rule bridge v2ray PREROUTING meta l4proto tcp ip daddr @LOCAL_IPV4 return
# nft add rule bridge v2ray PREROUTING meta l4proto tcp ip daddr @DEFAULT_ROUTE_IPV4 return

if [[ $TPROXY_SETUP_WITHOUT_IPV6 -eq 0 ]]; then
  ### ipv6 - skip multicast
  nft add rule bridge v2ray PREROUTING ip6 saddr @LOCAL_IPV6 pkttype '{broadcast, multicast}' accept
  nft add rule bridge v2ray PREROUTING ip6 daddr '{ ff00::/8 }' return
  ### ipv6 - skip link/unique-local fc00::/7,fe80::/10 and  ::1/128 are in ip -6 address show scope host/link
  nft add rule bridge v2ray PREROUTING ip6 daddr @LOCAL_IPV6 return
  nft add rule bridge v2ray PREROUTING ip6 daddr @DEFAULT_ROUTE_IPV6 return

  ### ipv6 - skip private network and UDP of DNS
  # if dns service and v2ray are on different server, use rules below
  # nft add rule bridge v2ray PREROUTING meta l4proto tcp ip6 daddr @LOCAL_IPV6 return
  # nft add rule bridge v2ray PREROUTING meta l4proto tcp ip6 daddr @DEFAULT_ROUTE_IPV6 return
  # nft add rule bridge v2ray PREROUTING ip6 daddr @LOCAL_IPV6 udp dport != 53 return
  # nft add rule bridge v2ray PREROUTING ip6 daddr @DEFAULT_ROUTE_IPV6 udp dport != 53 return
fi

### bridge - skip CN DNS
nft add rule bridge v2ray PREROUTING ip daddr "{ $SETUP_WITH_BLACKLIST_IPV4 }" return
if [[ $TPROXY_SETUP_WITHOUT_IPV6 -eq 0 ]]; then
  nft add rule bridge v2ray PREROUTING ip6 daddr "{ $SETUP_WITH_BLACKLIST_IPV6 }" return
fi

# bridge skip package from outside
# nft add rule bridge v2ray PREROUTING ip daddr @BLACKLIST return
# if [[ $TPROXY_SETUP_WITHOUT_IPV6 -eq 0 ]]; then
#     nft add rule bridge v2ray PREROUTING ip6 daddr @BLACKLIST return
# fi
if [ $TPROXY_SETUP_USING_GEOIP -ne 0 ]; then
  nft add rule bridge v2ray PREROUTING ip daddr @GEOIP_CN return
  # nft add rule bridge v2ray PREROUTING ip daddr @GEOIP_HK return
else
  ## Alternative: using whitlist
  if [[ $TPROXY_SETUP_WITHOUT_IPV6 -eq 0 ]]; then
    nft add rule bridge v2ray PREROUTING ip6 daddr != @TEMPORARY_WHITELIST_IPV6 ip6 daddr != @PERMANENT_WHITELIST_IPV6 return
  fi
  nft add rule bridge v2ray PREROUTING ip daddr != @TEMPORARY_WHITELIST_IPV4 ip daddr != @PERMANENT_WHITELIST_IPV4 return
fi

### bridge - meta pkttype set unicast
if [[ $SETUP_WITH_DEBUG_LOG -ne 0 ]]; then
  nft add rule bridge v2ray PREROUTING ip daddr != @LOCAL_IPV4 ip daddr != @DEFAULT_ROUTE_IPV4 meta nftrace set 1
  nft add rule bridge v2ray PREROUTING ip daddr != @LOCAL_IPV4 ip daddr != @DEFAULT_ROUTE_IPV4 log prefix '">>>BR TCP>pkttype:"' level debug flags all
  nft add rule bridge v2ray PREROUTING ip6 daddr != @LOCAL_IPV6 ip6 daddr != @DEFAULT_ROUTE_IPV6 meta nftrace set 1
  nft add rule bridge v2ray PREROUTING ip6 daddr != @LOCAL_IPV6 ip6 daddr != @DEFAULT_ROUTE_IPV6 log prefix '">>>BR TCP>pkttype:"' level debug flags all
fi

# https://www.mankier.com/8/ebtables-legacy#Description-Tables
# https://www.mankier.com/8/ebtables-nft
# Mac Address Assignments: https://www.iana.org/assignments/ethernet-numbers/ethernet-numbers.xml
# ebtables -t broute -A V2RAY_BRIDGE -j redirect --redirect-target DROP

nft add rule bridge v2ray PREROUTING meta pkttype set unicast ether daddr set ff:ff:ff:ff:ff:ff
