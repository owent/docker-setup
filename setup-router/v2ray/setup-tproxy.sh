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

if [[ "x" == "x$SETUP_WITH_DEBUG_LOG_RULE" ]]; then
  SETUP_WITH_DEBUG_LOG_RULE="-m set ! --match-set V2RAY_LOCAL_IPV4"
  if [[ $TPROXY_SETUP_WITHOUT_IPV6 -eq 0 ]]; then
    SETUP_WITH_DEBUG_LOG_RULE="$SETUP_WITH_DEBUG_LOG_RULE -m set ! --match-set V2RAY_LOCAL_IPV6"
  fi
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
  ip -6 route add local ::/0 dev lo table 100
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
  ip -6 route del local ::/0 dev lo table 100
fi
# ip route show table 100

### See https://toutyrater.github.io/app/tproxy.html

### Setup - ipv4
ipset list V2RAY_BLACKLIST_IPV4 >/dev/null 2>&1
if [[ $? -ne 0 ]]; then
  ipset create V2RAY_BLACKLIST_IPV4 hash:ip family inet
fi

for IP_ADDR in $(echo ${SETUP_WITH_BLACKLIST_IPV4//,/ }); do
  ipset add V2RAY_BLACKLIST_IPV4 $IP_ADDR -exist
done

if [[ $TPROXY_SETUP_USING_GEOIP -ne 0 ]]; then
  ipset list GEOIP_IPV4_CN >/dev/null 2>&1
  if [[ $? -ne 0 ]]; then
    ipset create GEOIP_IPV4_CN hash:net family inet
  fi
  ipset list GEOIP_IPV4_HK >/dev/null 2>&1
  if [[ $? -ne 0 ]]; then
    ipset create GEOIP_IPV4_HK hash:net family inet
  fi
fi

ipset list V2RAY_LOCAL_IPV4 >/dev/null 2>&1
if [[ $? -ne 0 ]]; then
  ipset create V2RAY_LOCAL_IPV4 hash:net family inet
  ipset add V2RAY_LOCAL_IPV4 0.0.0.0/8
  ipset add V2RAY_LOCAL_IPV4 10.0.0.0/8
  ipset add V2RAY_LOCAL_IPV4 127.0.0.0/8
  ipset add V2RAY_LOCAL_IPV4 169.254.0.0/16
  ipset add V2RAY_LOCAL_IPV4 172.16.0.0/12
  ipset add V2RAY_LOCAL_IPV4 192.0.0.0/24
  ipset add V2RAY_LOCAL_IPV4 192.168.0.0/16
  ipset add V2RAY_LOCAL_IPV4 224.0.0.0/4
  ipset add V2RAY_LOCAL_IPV4 240.0.0.0/4
fi
ipset list V2RAY_DEFAULT_ROUTE_IPV4 >/dev/null 2>&1
if [[ $? -ne 0 ]]; then
  ipset create V2RAY_DEFAULT_ROUTE_IPV4 hash:net family inet
fi
ipset list V2RAY_PROXY_DNS_IPV4 >/dev/null 2>&1
if [[ $? -ne 0 ]]; then
  ipset create V2RAY_PROXY_DNS_IPV4 hash:ip family inet
  ipset add V2RAY_PROXY_DNS_IPV4 8.8.8.8 -exist
  ipset add V2RAY_PROXY_DNS_IPV4 8.8.4.4 -exist
fi

iptables -t mangle -L V2RAY >/dev/null 2>&1
if [[ $? -ne 0 ]]; then
  iptables -t mangle -N V2RAY
else
  iptables -t mangle -F V2RAY
fi

iptables -t mangle -L V2RAY_MASK >/dev/null 2>&1
if [[ $? -ne 0 ]]; then
  iptables -t mangle -N V2RAY_MASK
else
  iptables -t mangle -F V2RAY_MASK
fi

### ipv4 - skip internal services
iptables -t mangle -A V2RAY -p tcp -m multiport --sports $ROUTER_INTERNAL_SERVICE_PORT_TCP -j RETURN
iptables -t mangle -A V2RAY -p udp -m multiport --sports $ROUTER_INTERNAL_SERVICE_PORT_UDP -j RETURN
iptables -t mangle -A V2RAY -p udp -m multiport --dports $ROUTER_INTERNAL_DIRECTLY_VISIT_UDP_DPORT -j RETURN
iptables -t mangle -A V2RAY -m set ! --match-set V2RAY_PROXY_DNS_IPV4 dst -p tcp -m multiport --dports "53,853" -j RETURN
iptables -t mangle -A V2RAY -m set ! --match-set V2RAY_PROXY_DNS_IPV4 dst -p udp -m multiport --dports "53,853" -j RETURN
if [[ $SETUP_WITH_DEBUG_LOG -ne 0 ]]; then
  iptables -t mangle -A V2RAY -p tcp $SETUP_WITH_DEBUG_LOG_RULE -j TRACE
  iptables -t mangle -A V2RAY -p tcp $SETUP_WITH_DEBUG_LOG_RULE -j LOG --log-level debug --log-prefix "###TCP4#PREROU:"
fi

### ipv4 - skip link-local and broadcast address
iptables -t mangle -A V2RAY -d 224.0.0.0/4,255.255.255.255/32 -j RETURN
iptables -t mangle -A V2RAY -m mark --mark 0x70/0x70 -j RETURN
### ipv4 - skip private network and UDP of DNS
iptables -t mangle -A V2RAY -m set --match-set V2RAY_LOCAL_IPV4 dst -j RETURN
iptables -t mangle -A V2RAY -m set --match-set V2RAY_DEFAULT_ROUTE_IPV4 dst -j RETURN
iptables -t mangle -A V2RAY -d 172.20.1.1/24 -j RETURN # 172.20.1.1/24 is used for remote debug
# if dns service and V2RAY are on different server, use rules below
# iptables -t mangle -A V2RAY -p tcp -m set --match-set V2RAY_LOCAL_IPV4 dst -j RETURN
# iptables -t mangle -A V2RAY -p tcp -m set --match-set V2RAY_DEFAULT_ROUTE_IPV4 dst -j RETURN
# iptables -t mangle -A V2RAY -p udp -m set --match-set V2RAY_LOCAL_IPV4 dst ! --dport 53 -j RETURN
# iptables -t mangle -A V2RAY -p udp -m set --match-set V2RAY_DEFAULT_ROUTE_IPV4 dst ! --dport 53 -j RETURN

# ipv4 skip package from outside
iptables -t mangle -A V2RAY -m set --match-set V2RAY_BLACKLIST_IPV4 dst -j RETURN
if [ $TPROXY_SETUP_USING_GEOIP -ne 0 ]; then
  iptables -t mangle -A V2RAY -m set --match-set GEOIP_IPV4_CN dst -j RETURN
# iptables -t mangle -A V2RAY -m set --match-set GEOIP_IPV4_HK dst -j RETURN
else
  iptables -t mangle -A V2RAY -m set ! --match-set DNSMASQ_GFW_IPV4 dst -j RETURN
fi
### ipv4 - forward to v2ray's listen address if not marked by v2ray
# tproxy ip to $V2RAY_HOST_IPV4:$V2RAY_PORT
if [[ $SETUP_WITH_DEBUG_LOG -ne 0 ]]; then
  # iptables -t mangle -A V2RAY -p tcp $SETUP_WITH_DEBUG_LOG_RULE -j TRACE
  iptables -t mangle -A V2RAY -p tcp $SETUP_WITH_DEBUG_LOG_RULE -j LOG --log-level debug --log-prefix ">>>TCP4>tproxy:"
fi

# --tproxy-mark here must match: ip rule list lookup 100
iptables -t mangle -A V2RAY -p tcp -j TPROXY --on-port $V2RAY_PORT --tproxy-mark 0x7e/0x7f # mark tcp package with 1 and forward to $V2RAY_PORT
iptables -t mangle -A V2RAY -p udp -j TPROXY --on-port $V2RAY_PORT --tproxy-mark 0x7e/0x7f # mark tcp package with 1 and forward to $V2RAY_PORT
if [[ $SETUP_WITH_DEBUG_LOG -ne 0 ]]; then
  # iptables -t mangle -A V2RAY -p tcp -m multiport $SETUP_WITH_DEBUG_LOG_RULE -j TRACE
  iptables -t mangle -A V2RAY -p tcp -m multiport $SETUP_WITH_DEBUG_LOG_RULE -j LOG --log-level debug --log-prefix ">>>TCP4>mark:0x70"
fi
iptables -t mangle -A V2RAY -m mark ! --mark 0x70/0x70 -j MARK --set-xmark 0x70/0x70
iptables -t mangle -A V2RAY -j CONNMARK --save-mark --mask 0xffff

# reset chain
iptables -t mangle -D PREROUTING -p tcp -j V2RAY >/dev/null 2>&1
while [[ $? -eq 0 ]]; do
  iptables -t mangle -D PREROUTING -p tcp -j V2RAY >/dev/null 2>&1
done
iptables -t mangle -D PREROUTING -p udp -j V2RAY >/dev/null 2>&1
while [[ $? -eq 0 ]]; do
  iptables -t mangle -D PREROUTING -p udp -j V2RAY >/dev/null 2>&1
done
iptables -t mangle -A PREROUTING -p tcp -j V2RAY # apply rules
iptables -t mangle -A PREROUTING -p udp -j V2RAY # apply rules

# Setup - ipv4 local
### ipv4 - skip internal services
iptables -t mangle -A V2RAY_MASK -p tcp -m multiport --sports $ROUTER_INTERNAL_SERVICE_PORT_TCP -j RETURN
iptables -t mangle -A V2RAY_MASK -p udp -m multiport --sports $ROUTER_INTERNAL_SERVICE_PORT_UDP -j RETURN
iptables -t mangle -A V2RAY_MASK -p udp -m multiport --dports $ROUTER_INTERNAL_DIRECTLY_VISIT_UDP_DPORT -j RETURN
iptables -t mangle -A V2RAY_MASK -m set ! --match-set V2RAY_PROXY_DNS_IPV4 dst -p tcp -m multiport --dports "53,853" -j RETURN
iptables -t mangle -A V2RAY_MASK -m set ! --match-set V2RAY_PROXY_DNS_IPV4 dst -p udp -m multiport --dports "53,853" -j RETURN
if [[ $SETUP_WITH_DEBUG_LOG -ne 0 ]]; then
  iptables -t mangle -A V2RAY_MASK -p tcp $SETUP_WITH_DEBUG_LOG_RULE -j LOG --log-level debug --log-prefix "###TCP4#OUTPUT:"
fi

iptables -t mangle -A V2RAY_MASK -d 224.0.0.0/4,255.255.255.255/32 -j RETURN
iptables -t mangle -A V2RAY_MASK -m mark --mark 0x70/0x70 -j RETURN
### ipv4 - skip private network and UDP of DNS
iptables -t mangle -A V2RAY_MASK -m set --match-set V2RAY_LOCAL_IPV4 dst -j RETURN
iptables -t mangle -A V2RAY_MASK -m set --match-set V2RAY_DEFAULT_ROUTE_IPV4 dst -j RETURN
iptables -t mangle -A V2RAY_MASK -d 172.20.1.1/24 -j RETURN # 172.20.1.1/24 is used for remote debug
# if dns service and V2RAY_MASK are on different server, use rules below
# iptables -t mangle -A V2RAY_MASK -p tcp -m set --match-set V2RAY_LOCAL_IPV4 dst -j RETURN
# iptables -t mangle -A V2RAY_MASK -p tcp -m set --match-set V2RAY_DEFAULT_ROUTE_IPV4 dst -j RETURN
# iptables -t mangle -A V2RAY_MASK -p udp -m set --match-set V2RAY_LOCAL_IPV4 dst ! --dport 53 -j RETURN
# iptables -t mangle -A V2RAY_MASK -p udp -m set --match-set V2RAY_DEFAULT_ROUTE_IPV4 dst ! --dport 53 -j RETURN
### ipv4 - skip CN DNS
iptables -t mangle -A V2RAY_MASK -m set --match-set V2RAY_BLACKLIST_IPV4 dst -j RETURN
if [ $TPROXY_SETUP_USING_GEOIP -ne 0 ]; then
  iptables -t mangle -A V2RAY_MASK -m set --match-set GEOIP_IPV4_CN dst -j RETURN
# iptables -t mangle -A V2RAY_MASK -m set --match-set GEOIP_IPV4_HK dst -j RETURN
else
  iptables -t mangle -A V2RAY_MASK -m set ! --match-set DNSMASQ_GFW_IPV4 dst -j RETURN
fi

if [[ $SETUP_WITH_DEBUG_LOG -ne 0 ]]; then
  # iptables -t mangle -A V2RAY_MASK -p tcp $SETUP_WITH_DEBUG_LOG_RULE -j TRACE
  iptables -t mangle -A V2RAY_MASK -p tcp $SETUP_WITH_DEBUG_LOG_RULE -j LOG --log-level debug --log-prefix "+++TCP4+mark 1:"
fi
# ipv4 skip package from outside
iptables -t mangle -A V2RAY_MASK -m mark ! --mark 0x0e/0x0f -j MARK --set-xmark 0x0e/0x0f
iptables -t mangle -A V2RAY_MASK -j CONNMARK --save-mark --mask 0xffff

# reset chain
iptables -t mangle -D OUTPUT -p tcp -j V2RAY_MASK >/dev/null 2>&1
while [[ $? -eq 0 ]]; do
  iptables -t mangle -D OUTPUT -p tcp -j V2RAY_MASK >/dev/null 2>&1
done
iptables -t mangle -D OUTPUT -p udp -j V2RAY_MASK >/dev/null 2>&1
while [[ $? -eq 0 ]]; do
  iptables -t mangle -D OUTPUT -p udp -j V2RAY_MASK >/dev/null 2>&1
done
iptables -t mangle -A OUTPUT -p tcp -j V2RAY_MASK # apply rules
iptables -t mangle -A OUTPUT -p udp -j V2RAY_MASK # apply rules

## Setup - ipv6
if [[ $TPROXY_SETUP_WITHOUT_IPV6 -eq 0 ]]; then
  ipset list V2RAY_BLACKLIST_IPV6 >/dev/null 2>&1
  if [ $? -ne 0 ]; then
    ipset create V2RAY_BLACKLIST_IPV6 hash:ip family inet6
  fi
  for IP_ADDR in $(echo ${SETUP_WITH_BLACKLIST_IPV6//,/ }); do
    ipset add V2RAY_BLACKLIST_IPV6 $IP_ADDR -exist
  done
  if [ $TPROXY_SETUP_USING_GEOIP -ne 0 ]; then
    ipset list GEOIP_IPV6_CN >/dev/null 2>&1
    if [ $? -ne 0 ]; then
      ipset create GEOIP_IPV6_CN hash:net family inet6
    fi
    ipset list GEOIP_IPV6_HK >/dev/null 2>&1
    if [[ $? -ne 0 ]]; then
      ipset create GEOIP_IPV6_HK hash:net family inet6
    fi
  fi
  ipset list V2RAY_LOCAL_IPV6 >/dev/null 2>&1
  if [[ $? -ne 0 ]]; then
    ipset create V2RAY_LOCAL_IPV6 hash:net family inet6
    ipset add V2RAY_LOCAL_IPV6 ::1/128
    ipset add V2RAY_LOCAL_IPV6 ::/128
    ipset add V2RAY_LOCAL_IPV6 ::ffff:0:0/96
    ipset add V2RAY_LOCAL_IPV6 64:ff9b::/96
    ipset add V2RAY_LOCAL_IPV6 100::/64
    ipset add V2RAY_LOCAL_IPV6 fc00::/7
    ipset add V2RAY_LOCAL_IPV6 fe80::/10
    ipset add V2RAY_LOCAL_IPV6 ff00::/8
  fi
  ipset list V2RAY_DEFAULT_ROUTE_IPV6 >/dev/null 2>&1
  if [[ $? -ne 0 ]]; then
    ipset create V2RAY_DEFAULT_ROUTE_IPV6 hash:net family inet6
  fi
  ipset list V2RAY_PROXY_DNS_IPV6 >/dev/null 2>&1
  if [[ $? -ne 0 ]]; then
    ipset create V2RAY_PROXY_DNS_IPV6 hash:ip family inet6
    ipset add V2RAY_PROXY_DNS_IPV6 '2001:4860:4860::8888' -exist
    ipset add V2RAY_PROXY_DNS_IPV6 '2001:4860:4860::8844' -exist
  fi

  ip6tables -t mangle -L V2RAY >/dev/null 2>&1
  if [[ $? -ne 0 ]]; then
    ip6tables -t mangle -N V2RAY
  else
    ip6tables -t mangle -F V2RAY
  fi

  ip6tables -t mangle -L V2RAY_MASK >/dev/null 2>&1
  if [[ $? -ne 0 ]]; then
    ip6tables -t mangle -N V2RAY_MASK
  else
    ip6tables -t mangle -F V2RAY_MASK
  fi

  ### ipv6 - skip internal services
  ip6tables -t mangle -A V2RAY -p tcp -m multiport --sports $ROUTER_INTERNAL_SERVICE_PORT_TCP -j RETURN
  ip6tables -t mangle -A V2RAY -p udp -m multiport --sports $ROUTER_INTERNAL_SERVICE_PORT_UDP -j RETURN
  ip6tables -t mangle -A V2RAY -p udp -m multiport --dports $ROUTER_INTERNAL_DIRECTLY_VISIT_UDP_DPORT -j RETURN
  ip6tables -t mangle -A V2RAY -m set ! --match-set V2RAY_PROXY_DNS_IPV6 dst -p tcp -m multiport --dports "53,853" -j RETURN
  ip6tables -t mangle -A V2RAY -m set ! --match-set V2RAY_PROXY_DNS_IPV6 dst -p udp -m multiport --dports "53,853" -j RETURN
  if [[ $SETUP_WITH_DEBUG_LOG -ne 0 ]]; then
    ip6tables -t mangle -A V2RAY -p tcp $SETUP_WITH_DEBUG_LOG_RULE -j LOG --log-level debug --log-prefix "###TCP6#PREROU:"
  fi

  ### ipv6 - skip link-locak and multicast
  ip6tables -t mangle -A V2RAY -m set --match-set V2RAY_LOCAL_IPV6 dst -j RETURN
  ip6tables -t mangle -A V2RAY -m set --match-set V2RAY_DEFAULT_ROUTE_IPV6 dst -j RETURN
  ip6tables -t mangle -A V2RAY -m mark --mark 0x70/0x70 -j RETURN
  ### ipv6 - skip private network and UDP of DNS
  # if dns service and V2RAY are on different server, use rules below
  # ip6tables -t mangle -A V2RAY -p tcp -m set --match-set V2RAY_LOCAL_IPV6 dst -j RETURN
  # ip6tables -t mangle -A V2RAY -p tcp -m set --match-set V2RAY_DEFAULT_ROUTE_IPV6 dst -j RETURN
  # ip6tables -t mangle -A V2RAY -p udp -m set --match-set V2RAY_LOCAL_IPV6 dst ! --dport 53 -j RETURN
  # ip6tables -t mangle -A V2RAY -p udp -m set --match-set V2RAY_DEFAULT_ROUTE_IPV6 dst ! --dport 53 -j RETURN

  # ipv6 skip package from outside
  ip6tables -t mangle -A V2RAY -m set --match-set V2RAY_BLACKLIST_IPV6 dst -j RETURN
  if [ $TPROXY_SETUP_USING_GEOIP -ne 0 ]; then
    ip6tables -t mangle -A V2RAY -m set --match-set GEOIP_IPV6_CN dst -j RETURN
  # ip6tables -t mangle -A V2RAY -m set --match-set GEOIP_IPV6_HK dst -j RETURN
  else
    ip6tables -t mangle -A V2RAY -m set ! --match-set DNSMASQ_GFW_IPV6 dst -j RETURN
  fi
  ### ipv6 - forward to v2ray's listen address if not marked by v2ray
  # tproxy ip to $V2RAY_HOST_IPV4:$V2RAY_PORT
  if [[ $SETUP_WITH_DEBUG_LOG -ne 0 ]]; then
    # ip6tables -t mangle -A V2RAY -p tcp $SETUP_WITH_DEBUG_LOG_RULE -j TRACE
    ip6tables -t mangle -A V2RAY -p tcp $SETUP_WITH_DEBUG_LOG_RULE -j LOG --log-level debug --log-prefix ">>>TCP6>tproxy:"
  fi

  # --tproxy-mark here must match: ip rule list lookup 100
  ip6tables -t mangle -A V2RAY -p tcp -j TPROXY --on-port $V2RAY_PORT --tproxy-mark 0x7e/0x7f # mark tcp package with 1 and forward to $V2RAY_PORT
  ip6tables -t mangle -A V2RAY -p udp -j TPROXY --on-port $V2RAY_PORT --tproxy-mark 0x7e/0x7f # mark tcp package with 1 and forward to $V2RAY_PORT
  if [[ $SETUP_WITH_DEBUG_LOG -ne 0 ]]; then
    # ip6tables -t mangle -A V2RAY -p tcp -m multiport ! --dports $ROUTER_INTERNAL_SERVICE_PORT_TCP -j TRACE
    ip6tables -t mangle -A V2RAY -p tcp -m multiport ! --dports $ROUTER_INTERNAL_SERVICE_PORT_TCP -j LOG --log-level debug --log-prefix ">>>TCP6>mark:0x70"
  fi
  ip6tables -t mangle -A V2RAY -m mark ! --mark 0x70/0x70 -j MARK --set-xmark 0x70/0x70
  ip6tables -t mangle -A V2RAY -j CONNMARK --save-mark --mask 0xffff

  # reset chain
  ip6tables -t mangle -D PREROUTING -p tcp -j V2RAY >/dev/null 2>&1
  while [[ $? -eq 0 ]]; do
    ip6tables -t mangle -D PREROUTING -p tcp -j V2RAY >/dev/null 2>&1
  done
  ip6tables -t mangle -D PREROUTING -p udp -j V2RAY >/dev/null 2>&1
  while [[ $? -eq 0 ]]; do
    ip6tables -t mangle -D PREROUTING -p udp -j V2RAY >/dev/null 2>&1
  done
  ip6tables -t mangle -A PREROUTING -p tcp -j V2RAY # apply rules
  ip6tables -t mangle -A PREROUTING -p udp -j V2RAY # apply rules

  # Setup - ipv6 local
  ### ipv6 - skip internal services
  ip6tables -t mangle -A V2RAY_MASK -p tcp -m multiport --sports $ROUTER_INTERNAL_SERVICE_PORT_TCP -j RETURN
  ip6tables -t mangle -A V2RAY_MASK -p udp -m multiport --sports $ROUTER_INTERNAL_SERVICE_PORT_UDP -j RETURN
  ip6tables -t mangle -A V2RAY_MASK -p udp -m multiport --dports $ROUTER_INTERNAL_DIRECTLY_VISIT_UDP_DPORT -j RETURN
  ip6tables -t mangle -A V2RAY_MASK -m set ! --match-set V2RAY_PROXY_DNS_IPV6 dst -p tcp -m multiport --dports "53,853" -j RETURN
  ip6tables -t mangle -A V2RAY_MASK -m set ! --match-set V2RAY_PROXY_DNS_IPV6 dst -p udp -m multiport --dports "53,853" -j RETURN
  if [[ $SETUP_WITH_DEBUG_LOG -ne 0 ]]; then
    ip6tables -t mangle -A V2RAY_MASK -p tcp $SETUP_WITH_DEBUG_LOG_RULE -j LOG --log-level debug --log-prefix "###TCP6#OUTPUT:"
  fi

  ip6tables -t mangle -A V2RAY_MASK -m set --match-set V2RAY_LOCAL_IPV6 dst -j RETURN
  ip6tables -t mangle -A V2RAY_MASK -m set --match-set V2RAY_DEFAULT_ROUTE_IPV6 dst -j RETURN
  ip6tables -t mangle -A V2RAY_MASK -m mark --mark 0x70/0x70 -j RETURN
  ### ipv6 - skip private network and UDP of DNS
  # if dns service and V2RAY_MASK are on different server, use rules below
  # ip6tables -t mangle -A V2RAY_MASK -p tcp -m set --match-set V2RAY_LOCAL_IPV6 dst -j RETURN
  # ip6tables -t mangle -A V2RAY_MASK -p tcp -m set --match-set V2RAY_DEFAULT_ROUTE_IPV6 dst -j RETURN
  # ip6tables -t mangle -A V2RAY_MASK -p udp -m set --match-set V2RAY_LOCAL_IPV6 dst ! --dport 53 -j RETURN
  # ip6tables -t mangle -A V2RAY_MASK -p udp -m set --match-set V2RAY_DEFAULT_ROUTE_IPV6 dst ! --dport 53 -j RETURN
  ### ipv6 - skip CN DNS
  ip6tables -t mangle -A V2RAY_MASK -d 2400:3200::1/128,2400:3200:baba::1/128,2400:da00::6666/128 -j RETURN
  ip6tables -t mangle -A V2RAY_MASK -m set --match-set V2RAY_BLACKLIST_IPV6 dst -j RETURN
  if [ $TPROXY_SETUP_USING_GEOIP -ne 0 ]; then
    ip6tables -t mangle -A V2RAY_MASK -m set --match-set GEOIP_IPV6_CN dst -j RETURN
  # ip6tables -t mangle -A V2RAY_MASK -m set --match-set GEOIP_IPV6_HK dst -j RETURN
  else
    ip6tables -t mangle -A V2RAY_MASK -m set ! --match-set DNSMASQ_GFW_IPV6 dst -j RETURN
  fi

  if [[ $SETUP_WITH_DEBUG_LOG -ne 0 ]]; then
    # ip6tables -t mangle -A V2RAY_MASK -p tcp $SETUP_WITH_DEBUG_LOG_RULE -j TRACE
    ip6tables -t mangle -A V2RAY_MASK -p tcp $SETUP_WITH_DEBUG_LOG_RULE -j LOG --log-level debug --log-prefix "+++TCP6+mark 1:"
  fi
  # ipv6 skip package from outside
  ip6tables -t mangle -A V2RAY_MASK -m mark ! --mark 0x0e/0x0f -j MARK --set-xmark 0x0e/0x0f
  ip6tables -t mangle -A V2RAY_MASK -j CONNMARK --save-mark --mask 0xffff

  # reset chain
  ip6tables -t mangle -D OUTPUT -p tcp -j V2RAY_MASK >/dev/null 2>&1
  while [[ $? -eq 0 ]]; do
    ip6tables -t mangle -D OUTPUT -p tcp -j V2RAY_MASK >/dev/null 2>&1
  done
  ip6tables -t mangle -D OUTPUT -p udp -j V2RAY_MASK >/dev/null 2>&1
  while [[ $? -eq 0 ]]; do
    ip6tables -t mangle -D OUTPUT -p udp -j V2RAY_MASK >/dev/null 2>&1
  done
  ip6tables -t mangle -A OUTPUT -p tcp -j V2RAY_MASK # apply rules
  ip6tables -t mangle -A OUTPUT -p udp -j V2RAY_MASK # apply rules
else
  ip6tables -t mangle -D PREROUTING -p tcp -j V2RAY >/dev/null 2>&1
  while [[ $? -eq 0 ]]; do
    ip6tables -t mangle -D PREROUTING -p tcp -j V2RAY >/dev/null 2>&1
  done
  ip6tables -t mangle -D PREROUTING -p udp -j V2RAY >/dev/null 2>&1
  while [[ $? -eq 0 ]]; do
    ip6tables -t mangle -D PREROUTING -p udp -j V2RAY >/dev/null 2>&1
  done

  ip6tables -t mangle -D OUTPUT -p tcp -j V2RAY_MASK >/dev/null 2>&1
  while [[ $? -eq 0 ]]; do
    ip6tables -t mangle -D OUTPUT -p tcp -j V2RAY_MASK >/dev/null 2>&1
  done
  ip6tables -t mangle -D OUTPUT -p udp -j V2RAY_MASK >/dev/null 2>&1
  while [[ $? -eq 0 ]]; do
    ip6tables -t mangle -D OUTPUT -p udp -j V2RAY_MASK >/dev/null 2>&1
  done

  ip6tables -t mangle -F V2RAY
  ip6tables -t mangle -X V2RAY
  ip6tables -t mangle -F V2RAY_MASK
  ip6tables -t mangle -X V2RAY_MASK
fi

## Setup - bridge
SETUP_TPROXY_EBTABLES_SCRIPT="$(cd "$(dirname "$0")" && pwd)/setup-tproxy.ebtables.sh"
bash "$SETUP_TPROXY_EBTABLES_SCRIPT"

ln -sf "$SETUP_TPROXY_EBTABLES_SCRIPT" /etc/NetworkManager/dispatcher.d/up.d/99-setup-tproxy.ebtables.sh
ln -sf "$SETUP_TPROXY_EBTABLES_SCRIPT" /etc/NetworkManager/dispatcher.d/down.d/99-setup-tproxy.ebtables.sh
