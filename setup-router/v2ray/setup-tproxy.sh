#!/bin/bash

set -x

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

if [[ -e "/opt/nftables/sbin" ]]; then
  export PATH=/opt/nftables/sbin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/bin/site_perl:/usr/bin/vendor_perl:/usr/bin/core_perl
else
  export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/bin/site_perl:/usr/bin/vendor_perl:/usr/bin/core_perl
fi

### ==================================== v2ray nftables rules begin ====================================
### ----------------------------------- /home/router/v2ray/setup-tproxy.sh -----------------------------------

### Setup v2ray xtable rule and policy routing
### ip rule { add | del } SELECTOR ACTION
### default table/rule-> local(ID: 255)/Priority: 0 , main(ID: 254)/Priority: 32766 , default(ID: 253)/Priority: 32766
### 策略路由(占用mark的后8位):
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

if [[ "x" == "x$SETUP_WITH_INTERNAL_SERVICE_PORT" ]]; then
  SETUP_WITH_INTERNAL_SERVICE_PORT="22,53,6881,6882,6883,8371,8372,8381,8382,36000"
fi

if [[ "x" == "x$SETUP_WITH_DEBUG_LOG_IGNORE_PORT" ]]; then
  SETUP_WITH_DEBUG_LOG_IGNORE_PORT="22,53,6881,6882,6883,8382,36000"
fi

if [[ "x" == "x$SETUP_WITH_DIRECTLY_VISIT_UDP_DPORT" ]]; then
  # NTP Port: 123
  SETUP_WITH_DIRECTLY_VISIT_UDP_DPORT="123"
fi

if [[ "x" == "x$SETUP_WITH_DEBUG_LOG" ]]; then
  SETUP_WITH_DEBUG_LOG=0
fi

if [[ "x$SETUP_WITHOUT_IPV6" != "x" ]] && [[ "x$SETUP_WITHOUT_IPV6" != "x0" ]] && [[ "x$SETUP_WITHOUT_IPV6" != "xfalse" ]] && [[ "x$SETUP_WITHOUT_IPV6" != "xno" ]]; then
  V2RAY_SETUP_SKIP_IPV6=1
else
  V2RAY_SETUP_SKIP_IPV6=0
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

if [[ $V2RAY_SETUP_SKIP_IPV6 -eq 0 ]]; then
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
ipset list GEOIP_IPV4_CN >/dev/null 2>&1
if [[ $? -ne 0 ]]; then
  ipset create GEOIP_IPV4_CN hash:net family inet
fi
ipset list GEOIP_IPV4_HK >/dev/null 2>&1
if [[ $? -ne 0 ]]; then
  ipset create GEOIP_IPV4_HK hash:net family inet
fi
ipset list V2RAY_LOCAL_IPV4 >/dev/null 2>&1
if [[ $? -ne 0 ]]; then
  ipset create V2RAY_LOCAL_IPV4 hash:net family inet
  ipset add V2RAY_LOCAL_IPV4 127.0.0.1/32
  ipset add V2RAY_LOCAL_IPV4 192.168.0.0/16
  ipset add V2RAY_LOCAL_IPV4 172.16.0.0/12
  ipset add V2RAY_LOCAL_IPV4 10.0.0.0/8
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
iptables -t mangle -A V2RAY -p tcp -m multiport --sports $SETUP_WITH_INTERNAL_SERVICE_PORT -j RETURN
iptables -t mangle -A V2RAY -p udp -m multiport --sports $SETUP_WITH_INTERNAL_SERVICE_PORT -j RETURN
iptables -t mangle -A V2RAY -p udp -m multiport --dports $SETUP_WITH_DIRECTLY_VISIT_UDP_DPORT -j RETURN
if [[ $SETUP_WITH_DEBUG_LOG -ne 0 ]]; then
  iptables -t mangle -A V2RAY -p tcp -m multiport ! --dports $SETUP_WITH_DEBUG_LOG_IGNORE_PORT -j TRACE
  iptables -t mangle -A V2RAY -p tcp -m multiport ! --dports $SETUP_WITH_DEBUG_LOG_IGNORE_PORT -j LOG --log-level debug --log-prefix "###TCP4#PREROU:"
fi

### ipv4 - skip link-local and broadcast address
iptables -t mangle -A V2RAY 224.0.0.0/4,255.255.255.255/32 -j RETURN
iptables -t mangle -A V2RAY -m mark --mark 0x70/0x70 -j RETURN
### ipv4 - skip private network and UDP of DNS
iptables -t mangle -A V2RAY -m set --match-set V2RAY_LOCAL_IPV4 dst -j RETURN
iptables -t mangle -A V2RAY -d 172.20.1.1/24 -j RETURN # 172.20.1.1/24 is used for remote debug
# if dns service and V2RAY are on different server, use rules below
# iptables -t mangle -A V2RAY -p tcp -m set --match-set V2RAY_LOCAL_IPV4 dst -j RETURN
# iptables -t mangle -A V2RAY -p udp -m set --match-set V2RAY_LOCAL_IPV4 dst ! --dport 53 -j RETURN
### ipv4 - skip CN DNS
iptables -t mangle -A V2RAY -d 119.29.29.29/32,223.5.5.5/32,223.6.6.6/32,180.76.76.76/32 -j RETURN

# ipv4 skip package from outside
iptables -t mangle -A V2RAY -m set --match-set V2RAY_BLACKLIST_IPV4 dst -j RETURN
iptables -t mangle -A V2RAY -m set --match-set GEOIP_IPV4_CN dst -j RETURN
# iptables -t mangle -A V2RAY -m set --match-set GEOIP_IPV4_HK dst -j RETURN
# iptables -t mangle -A V2RAY -m set ! --match-set DNSMASQ_GFW_IPV4 dst -j RETURN
### ipv4 - forward to v2ray's listen address if not marked by v2ray
# tproxy ip to $V2RAY_HOST_IPV4:$V2RAY_PORT
if [[ $SETUP_WITH_DEBUG_LOG -ne 0 ]]; then
  # iptables -t mangle -A V2RAY -p tcp -m multiport ! --dports $SETUP_WITH_DEBUG_LOG_IGNORE_PORT -j TRACE
  iptables -t mangle -A V2RAY -p tcp -m multiport ! --dports $SETUP_WITH_DEBUG_LOG_IGNORE_PORT -j LOG --log-level debug --log-prefix ">>>TCP4>tproxy:"
fi

# --tproxy-mark here must match: ip rule list lookup 100
iptables -t mangle -A V2RAY -p tcp -j TPROXY --on-port $V2RAY_PORT --tproxy-mark 0x7e/0x7f # mark tcp package with 1 and forward to $V2RAY_PORT
iptables -t mangle -A V2RAY -p udp -j TPROXY --on-port $V2RAY_PORT --tproxy-mark 0x7e/0x7f # mark tcp package with 1 and forward to $V2RAY_PORT
if [[ $SETUP_WITH_DEBUG_LOG -ne 0 ]]; then
  # iptables -t mangle -A V2RAY -p tcp -m multiport ! --dports $SETUP_WITH_DEBUG_LOG_IGNORE_PORT -j TRACE
  iptables -t mangle -A V2RAY -p tcp -m multiport ! --dports $SETUP_WITH_DEBUG_LOG_IGNORE_PORT -j LOG --log-level debug --log-prefix ">>>TCP4>mark:0x70"
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
iptables -t mangle -A V2RAY_MASK -p tcp -m multiport --sports $SETUP_WITH_INTERNAL_SERVICE_PORT -j RETURN
iptables -t mangle -A V2RAY_MASK -p udp -m multiport --sports $SETUP_WITH_INTERNAL_SERVICE_PORT -j RETURN
iptables -t mangle -A V2RAY_MASK -p udp -m multiport --dports $SETUP_WITH_DIRECTLY_VISIT_UDP_DPORT -j RETURN
if [[ $SETUP_WITH_DEBUG_LOG -ne 0 ]]; then
  iptables -t mangle -A V2RAY_MASK -p tcp -m multiport ! --dports $SETUP_WITH_DEBUG_LOG_IGNORE_PORT -j LOG --log-level debug --log-prefix "###TCP4#OUTPUT:"
fi

iptables -t mangle -A V2RAY_MASK -d 224.0.0.0/4,255.255.255.255/32 -j RETURN
iptables -t mangle -A V2RAY_MASK -m mark --mark 0x70/0x70 -j RETURN
### ipv4 - skip private network and UDP of DNS
iptables -t mangle -A V2RAY_MASK -m set --match-set V2RAY_LOCAL_IPV4 dst -j RETURN
iptables -t mangle -A V2RAY_MASK -d 172.20.1.1/24 -j RETURN # 172.20.1.1/24 is used for remote debug
# if dns service and V2RAY_MASK are on different server, use rules below
# iptables -t mangle -A V2RAY_MASK -p tcp -m set --match-set V2RAY_LOCAL_IPV4 dst -j RETURN
# iptables -t mangle -A V2RAY_MASK -p udp -m set --match-set V2RAY_LOCAL_IPV4 dst ! --dport 53 -j RETURN
### ipv4 - skip CN DNS
iptables -t mangle -A V2RAY_MASK -d 119.29.29.29/32,223.5.5.5/32,223.6.6.6/32,180.76.76.76/32 -j RETURN
iptables -t mangle -A V2RAY_MASK -m set --match-set V2RAY_BLACKLIST_IPV4 dst -j RETURN
iptables -t mangle -A V2RAY_MASK -m set --match-set GEOIP_IPV4_CN dst -j RETURN
# iptables -t mangle -A V2RAY_MASK -m set --match-set GEOIP_IPV4_HK dst -j RETURN
# iptables -t mangle -A V2RAY_MASK -m set --match-set DNSMASQ_GFW_IPV4 dst -j RETURN

if [[ $SETUP_WITH_DEBUG_LOG -ne 0 ]]; then
  # iptables -t mangle -A V2RAY_MASK -p tcp -m multiport ! --dports $SETUP_WITH_DEBUG_LOG_IGNORE_PORT -j TRACE
  iptables -t mangle -A V2RAY_MASK -p tcp -m multiport ! --dports $SETUP_WITH_DEBUG_LOG_IGNORE_PORT -j LOG --log-level debug --log-prefix "+++TCP4+mark 1:"
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
if [[ $V2RAY_SETUP_SKIP_IPV6 -eq 0 ]]; then
  ipset list V2RAY_BLACKLIST_IPV6 >/dev/null 2>&1
  if [ $? -ne 0 ]; then
    ipset create V2RAY_BLACKLIST_IPV6 hash:ip family inet6
  fi
  ipset list GEOIP_IPV6_CN >/dev/null 2>&1
  if [ $? -ne 0 ]; then
    ipset create GEOIP_IPV6_CN hash:net family inet6
  fi
  ipset list GEOIP_IPV6_HK >/dev/null 2>&1
  if [[ $? -ne 0 ]]; then
    ipset create GEOIP_IPV6_HK hash:net family inet6
  fi
  ipset list V2RAY_LOCAL_IPV6 >/dev/null 2>&1
  if [[ $? -ne 0 ]]; then
    ipset create V2RAY_LOCAL_IPV6 hash:net family inet6
    ipset add V2RAY_LOCAL_IPV6 ::1/128
    ipset add V2RAY_LOCAL_IPV6 fc00::/7
    ipset add V2RAY_LOCAL_IPV6 fe80::/10
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
  ip6tables -t mangle -A V2RAY -p tcp -m multiport --sports $SETUP_WITH_INTERNAL_SERVICE_PORT -j RETURN
  ip6tables -t mangle -A V2RAY -p udp -m multiport --sports $SETUP_WITH_INTERNAL_SERVICE_PORT -j RETURN
  ip6tables -t mangle -A V2RAY -p udp -m multiport --dports $SETUP_WITH_DIRECTLY_VISIT_UDP_DPORT -j RETURN
  if [[ $SETUP_WITH_DEBUG_LOG -ne 0 ]]; then
    ip6tables -t mangle -A V2RAY -p tcp -m multiport ! --dports $SETUP_WITH_DEBUG_LOG_IGNORE_PORT -j LOG --log-level debug --log-prefix "###TCP6#PREROU:"
  fi

  ### ipv6 - skip link-locak and multicast
  ip6tables -t mangle -A V2RAY -m set --match-set V2RAY_LOCAL_IPV6 dst -j RETURN
  ip6tables -t mangle -A V2RAY -m mark --mark 0x70/0x70 -j RETURN
  ### ipv6 - skip private network and UDP of DNS
  # if dns service and V2RAY are on different server, use rules below
  # ip6tables -t mangle -A V2RAY -p tcp -m set --match-set V2RAY_LOCAL_IPV6 dst -j RETURN
  # ip6tables -t mangle -A V2RAY -p udp -m set --match-set V2RAY_LOCAL_IPV6 dst ! --dport 53 -j RETURN
  ### ipv6 - skip CN DNS
  ip6tables -t mangle -A V2RAY -d 2400:3200::1/128,2400:3200:baba::1/128,2400:da00::6666/128 -j RETURN

  # ipv6 skip package from outside
  ip6tables -t mangle -A V2RAY -d ff00::/8 -j RETURN
  ip6tables -t mangle -A V2RAY -m set --match-set V2RAY_BLACKLIST_IPV6 dst -j RETURN
  ip6tables -t mangle -A V2RAY -m set --match-set GEOIP_IPV6_CN dst -j RETURN
  # ip6tables -t mangle -A V2RAY -m set --match-set GEOIP_IPV6_HK dst -j RETURN
  # ip6tables -t mangle -A V2RAY -m set ! --match-set DNSMASQ_GFW_IPV6 dst -j RETURN
  ### ipv6 - forward to v2ray's listen address if not marked by v2ray
  # tproxy ip to $V2RAY_HOST_IPV4:$V2RAY_PORT
  if [[ $SETUP_WITH_DEBUG_LOG -ne 0 ]]; then
    # ip6tables -t mangle -A V2RAY -p tcp -m multiport ! --dports $SETUP_WITH_DEBUG_LOG_IGNORE_PORT -j TRACE
    ip6tables -t mangle -A V2RAY -p tcp -m multiport ! --dports $SETUP_WITH_DEBUG_LOG_IGNORE_PORT -j LOG --log-level debug --log-prefix ">>>TCP6>tproxy:"
  fi

  # --tproxy-mark here must match: ip rule list lookup 100
  ip6tables -t mangle -A V2RAY -p tcp -j TPROXY --on-port $V2RAY_PORT --tproxy-mark 0x7e/0x7f # mark tcp package with 1 and forward to $V2RAY_PORT
  ip6tables -t mangle -A V2RAY -p udp -j TPROXY --on-port $V2RAY_PORT --tproxy-mark 0x7e/0x7f # mark tcp package with 1 and forward to $V2RAY_PORT
  if [[ $SETUP_WITH_DEBUG_LOG -ne 0 ]]; then
    # ip6tables -t mangle -A V2RAY -p tcp -m multiport ! --dports $SETUP_WITH_INTERNAL_SERVICE_PORT -j TRACE
    ip6tables -t mangle -A V2RAY -p tcp -m multiport ! --dports $SETUP_WITH_INTERNAL_SERVICE_PORT -j LOG --log-level debug --log-prefix ">>>TCP6>mark:0x70"
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
  ip6tables -t mangle -A V2RAY_MASK -p tcp -m multiport --sports $SETUP_WITH_INTERNAL_SERVICE_PORT -j RETURN
  ip6tables -t mangle -A V2RAY_MASK -p udp -m multiport --sports $SETUP_WITH_INTERNAL_SERVICE_PORT -j RETURN
  ip6tables -t mangle -A V2RAY_MASK -p udp -m multiport --dports $SETUP_WITH_DIRECTLY_VISIT_UDP_DPORT -j RETURN
  if [[ $SETUP_WITH_DEBUG_LOG -ne 0 ]]; then
    ip6tables -t mangle -A V2RAY_MASK -p tcp -m multiport ! --dports $SETUP_WITH_DEBUG_LOG_IGNORE_PORT -j LOG --log-level debug --log-prefix "###TCP6#OUTPUT:"
  fi

  ip6tables -t mangle -A V2RAY_MASK -m set --match-set V2RAY_LOCAL_IPV6 dst -j RETURN
  ip6tables -t mangle -A V2RAY_MASK -m mark --mark 0x70/0x70 -j RETURN
  ### ipv6 - skip private network and UDP of DNS
  # if dns service and V2RAY_MASK are on different server, use rules below
  # ip6tables -t mangle -A V2RAY_MASK -p tcp -m set --match-set V2RAY_LOCAL_IPV6 dst -j RETURN
  # ip6tables -t mangle -A V2RAY_MASK -p udp -m set --match-set V2RAY_LOCAL_IPV6 dst ! --dport 53 -j RETURN
  ### ipv6 - skip CN DNS
  ip6tables -t mangle -A V2RAY_MASK -d 2400:3200::1/128,2400:3200:baba::1/128,2400:da00::6666/128 -j RETURN
  ip6tables -t mangle -A V2RAY_MASK -d ff00::/8 -j RETURN
  ip6tables -t mangle -A V2RAY_MASK -m set --match-set V2RAY_BLACKLIST_IPV6 dst -j RETURN
  ip6tables -t mangle -A V2RAY_MASK -m set --match-set GEOIP_IPV6_CN dst -j RETURN
  # ip6tables -t mangle -A V2RAY_MASK -m set --match-set GEOIP_IPV6_HK dst -j RETURN
  # ip6tables -t mangle -A V2RAY_MASK -m set --match-set DNSMASQ_GFW_IPV6 dst -j RETURN

  if [[ $SETUP_WITH_DEBUG_LOG -ne 0 ]]; then
    # ip6tables -t mangle -A V2RAY_MASK -p tcp -m multiport ! --dports $SETUP_WITH_DEBUG_LOG_IGNORE_PORT -j TRACE
    ip6tables -t mangle -A V2RAY_MASK -p tcp -m multiport ! --dports $SETUP_WITH_DEBUG_LOG_IGNORE_PORT -j LOG --log-level debug --log-prefix "+++TCP6+mark 1:"
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
SETUP_TPROXY_EBTABLES_SCRIPT="$(cd "$(dirname "$0")" && pwd)/setup-tproxy.ebtables.sh";
bash "$SETUP_TPROXY_EBTABLES_SCRIPT"

ln -sf "$SETUP_TPROXY_EBTABLES_SCRIPT" /etc/NetworkManager/dispatcher.d/up.d/99-setup-tproxy.ebtables.sh
ln -sf "$SETUP_TPROXY_EBTABLES_SCRIPT" /etc/NetworkManager/dispatcher.d/down.d/99-setup-tproxy.ebtables.sh

