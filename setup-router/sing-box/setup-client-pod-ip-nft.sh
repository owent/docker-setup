#!/bin/bash

# $ROUTER_HOME/sing-box/create-client-pod.sh
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

if [[ -z "$VBOX_DATA_DIR" ]]; then
  VBOX_DATA_DIR="$HOME/vbox/data"
fi

### 策略路由(占用mark的后4位,RPDB变化均会触发重路由, meta mark and 0x0f != 0x0 都跳过重路由):
###   不需要重路由设置: meta mark and 0x0f != 0x0
###   走 tun: 设置 fwmark = 0x03/0x03 (0011)
###   直接跳转到默认路由: 跳过 fwmark = 0x0c/0x0c (1100)
###     (vbox会设置511,0x1ff), 避开 meta mark and 0x0f != 0x0 规则 (防止循环重定向)

if [[ -z "$ROUTER_IP_RULE_GOTO_DEFAULT_PRIORITY" ]]; then
  ROUTER_IP_RULE_GOTO_DEFAULT_PRIORITY=20901
fi
if [[ -z "$VBOX_SKIP_IP_RULE_PRIORITY" ]]; then
  VBOX_SKIP_IP_RULE_PRIORITY=8123
fi

if [[ $ROUTER_NET_LOCAL_ENABLE_VBOX -ne 0 ]] && [[ "x$1" != "xclear" ]]; then
  VBOX_SETUP_IP_RULE_CLEAR=1
else
  VBOX_SETUP_IP_RULE_CLEAR=0
fi

if [[ ${#VBOX_BLACKLIST_VLAN_IDS[@]} -gt 0 ]]; then
  SETUP_WITH_BLACKLIST_VLAN_IDS="{"
  for VLAN_TAG in "${VBOX_BLACKLIST_VLAN_IDS[@]}"; do
    SETUP_WITH_BLACKLIST_VLAN_IDS="$SETUP_WITH_BLACKLIST_VLAN_IDS$VLAN_TAG,"
  done
  SETUP_WITH_BLACKLIST_VLAN_IDS="${SETUP_WITH_BLACKLIST_VLAN_IDS::-1}}"
else
  SETUP_WITH_BLACKLIST_VLAN_IDS=""
fi

if [ $VBOX_SETUP_IP_RULE_CLEAR -ne 0 ]; then
  if [[ -e "$VBOX_DATA_DIR/geoip-cn.json" ]] && [[ -e "$VBOX_DATA_DIR/geoip-cn.json.bak" ]]; then
    rm -f "$VBOX_DATA_DIR/geoip-cn.json.bak"
  fi
  if [[ -e "$VBOX_DATA_DIR/geoip-cn.json" ]]; then
    mv -f "$VBOX_DATA_DIR/geoip-cn.json" "$VBOX_DATA_DIR/geoip-cn.json.bak"
  fi

  podman exec -it vbox-client vbox geoip export cn -f /usr/share/vbox/geoip.db -o /usr/share/vbox/geoip-cn.json
  podman cp vbox-client:/usr/share/vbox/geoip-cn.json "$VBOX_DATA_DIR/geoip-cn.json" || mv -f "$VBOX_DATA_DIR/geoip-cn.json.bak" "$VBOX_DATA_DIR/geoip-cn.json"
fi

# Sing-box has poor performance, we route by ip first
ROUTER_IP_RULE_LOOPUP_PRIORITY_NOP=$(ip -4 rule show priority $ROUTER_IP_RULE_GOTO_DEFAULT_PRIORITY | awk 'END {print NF}')
while [[ 0 -ne $ROUTER_IP_RULE_LOOPUP_PRIORITY_NOP ]]; do
  ip -4 rule delete priority $ROUTER_IP_RULE_GOTO_DEFAULT_PRIORITY
  ROUTER_IP_RULE_LOOPUP_PRIORITY_NOP=$(ip -4 rule show priority $ROUTER_IP_RULE_GOTO_DEFAULT_PRIORITY | awk 'END {print NF}')
done

ROUTER_IP_RULE_LOOPUP_PRIORITY_NOP=$(ip -6 rule show priority $ROUTER_IP_RULE_GOTO_DEFAULT_PRIORITY | awk 'END {print NF}')
while [[ 0 -ne $ROUTER_IP_RULE_LOOPUP_PRIORITY_NOP ]]; do
  ip -6 rule delete priority $ROUTER_IP_RULE_GOTO_DEFAULT_PRIORITY
  ROUTER_IP_RULE_LOOPUP_PRIORITY_NOP=$(ip -6 rule show priority $ROUTER_IP_RULE_GOTO_DEFAULT_PRIORITY | awk 'END {print NF}')
done

ROUTER_IP_RULE_LOOPUP_VBOX_SKIP_PRIORITY=$(ip -4 rule show priority $VBOX_SKIP_IP_RULE_PRIORITY | awk 'END {print NF}')
while [[ 0 -ne $ROUTER_IP_RULE_LOOPUP_VBOX_SKIP_PRIORITY ]]; do
  ip -4 rule delete priority $VBOX_SKIP_IP_RULE_PRIORITY
  ROUTER_IP_RULE_LOOPUP_VBOX_SKIP_PRIORITY=$(ip -4 rule show priority $VBOX_SKIP_IP_RULE_PRIORITY | awk 'END {print NF}')
done

ROUTER_IP_RULE_LOOPUP_VBOX_SKIP_PRIORITY=$(ip -6 rule show priority $VBOX_SKIP_IP_RULE_PRIORITY | awk 'END {print NF}')
while [[ 0 -ne $ROUTER_IP_RULE_LOOPUP_VBOX_SKIP_PRIORITY ]]; do
  ip -6 rule delete priority $VBOX_SKIP_IP_RULE_PRIORITY
  ROUTER_IP_RULE_LOOPUP_VBOX_SKIP_PRIORITY=$(ip -6 rule show priority $VBOX_SKIP_IP_RULE_PRIORITY | awk 'END {print NF}')
done

function vbox_setup_rule_marks() {
  FAMILY="$1"
  TABLE="$2"

  # POLICY_MARK_GOTO_DEFAULT
  nft list chain $FAMILY $TABLE POLICY_MARK_GOTO_DEFAULT >/dev/null 2>&1
  if [[ $? -ne 0 ]]; then
    nft add chain $FAMILY $TABLE POLICY_MARK_GOTO_DEFAULT
  fi
  nft flush chain $FAMILY $TABLE POLICY_MARK_GOTO_DEFAULT
  nft add rule $FAMILY $TABLE POLICY_MARK_GOTO_DEFAULT meta mark set meta mark and 0xfffffff0 xor 0x0c
  nft add rule $FAMILY $TABLE POLICY_MARK_GOTO_DEFAULT ct mark set meta mark accept

  # POLICY_MARK_GOTO_TUN
  nft list chain $FAMILY $TABLE POLICY_MARK_GOTO_TUN >/dev/null 2>&1
  if [[ $? -ne 0 ]]; then
    nft add chain $FAMILY $TABLE POLICY_MARK_GOTO_TUN
  fi
  nft flush chain $FAMILY $TABLE POLICY_MARK_GOTO_TUN
  nft add rule $FAMILY $TABLE POLICY_MARK_GOTO_TUN meta mark set meta mark and 0xfffffff0 xor 0x03
  nft add rule $FAMILY $TABLE POLICY_MARK_GOTO_TUN ct mark set meta mark accept
}

function vbox_iniitialize_rule_table_ipv4() {
  FAMILY="$1"
  TABLE="$2"

  nft list set $FAMILY $TABLE BLACKLIST_IPV4 >/dev/null 2>&1
  if [[ $? -ne 0 ]]; then
    nft add set $FAMILY $TABLE BLACKLIST_IPV4 '{ type ipv4_addr; }'
  fi
  nft list set $FAMILY $TABLE GEOIP_CN_IPV4 >/dev/null 2>&1
  if [[ $? -ne 0 ]]; then
    nft add set $FAMILY $TABLE GEOIP_CN_IPV4 '{ type ipv4_addr; flags interval; auto-merge; }'
  fi
  nft list set $FAMILY $TABLE LOCAL_IPV4 >/dev/null 2>&1
  if [[ $? -ne 0 ]]; then
    nft add set $FAMILY $TABLE LOCAL_IPV4 '{ type ipv4_addr; flags interval; auto-merge; }'
    nft add element $FAMILY $TABLE LOCAL_IPV4 '{127.0.0.1/32, 169.254.0.0/16, 192.168.0.0/16, 172.16.0.0/12, 10.0.0.0/8}'
  fi
  nft list set $FAMILY $TABLE DEFAULT_ROUTE_IPV4 >/dev/null 2>&1
  if [[ $? -ne 0 ]]; then
    nft add set $FAMILY $TABLE DEFAULT_ROUTE_IPV4 '{ type ipv4_addr; flags interval; auto-merge ; }'
  fi

  # POLICY_VBOX_IPV4
  nft list chain $FAMILY $TABLE POLICY_VBOX_IPV4 >/dev/null 2>&1
  if [[ $? -ne 0 ]]; then
    nft add chain $FAMILY $TABLE POLICY_VBOX_IPV4
  fi
  nft flush chain $FAMILY $TABLE POLICY_VBOX_IPV4

  # ipv4 - local network
  nft add rule $FAMILY $TABLE POLICY_VBOX_IPV4 ip saddr @LOCAL_IPV4 ip daddr @LOCAL_IPV4 jump POLICY_MARK_GOTO_DEFAULT

  # ipv4 - DNAT or connect from outside
  nft add rule $FAMILY $TABLE POLICY_VBOX_IPV4 ip saddr @LOCAL_IPV4 tcp sport "{$ROUTER_INTERNAL_SERVICE_PORT_TCP}" jump POLICY_MARK_GOTO_DEFAULT
  nft add rule $FAMILY $TABLE POLICY_VBOX_IPV4 ip saddr @LOCAL_IPV4 udp sport "{$ROUTER_INTERNAL_SERVICE_PORT_UDP}" jump POLICY_MARK_GOTO_DEFAULT
  nft add rule $FAMILY $TABLE POLICY_VBOX_IPV4 ip saddr @DEFAULT_ROUTE_IPV4 tcp sport "{$ROUTER_INTERNAL_SERVICE_PORT_TCP}" jump POLICY_MARK_GOTO_DEFAULT
  nft add rule $FAMILY $TABLE POLICY_VBOX_IPV4 ip saddr @DEFAULT_ROUTE_IPV4 udp sport "{$ROUTER_INTERNAL_SERVICE_PORT_UDP}" jump POLICY_MARK_GOTO_DEFAULT
  nft add rule $FAMILY $TABLE POLICY_VBOX_IPV4 tcp dport "{$ROUTER_INTERNAL_DIRECTLY_VISIT_UDP_DPORT}" jump POLICY_MARK_GOTO_DEFAULT
  nft add rule $FAMILY $TABLE POLICY_VBOX_IPV4 udp dport "{$ROUTER_INTERNAL_DIRECTLY_VISIT_UDP_DPORT}" jump POLICY_MARK_GOTO_DEFAULT

  ### ipv4 - skip link-local and broadcast address, 172.20.1.1/24 is used for remote debug
  nft add rule $FAMILY $TABLE POLICY_VBOX_IPV4 ip daddr {224.0.0.0/4, 255.255.255.255/32, 172.20.1.1/24} jump POLICY_MARK_GOTO_DEFAULT

  ### ipv4 - skip private network and UDP of DNS
  nft add rule $FAMILY $TABLE POLICY_VBOX_IPV4 ip daddr @LOCAL_IPV4 tcp dport "{$ROUTER_INTERNAL_SERVICE_PORT_TCP}" jump POLICY_MARK_GOTO_DEFAULT
  nft add rule $FAMILY $TABLE POLICY_VBOX_IPV4 ip daddr @LOCAL_IPV4 udp dport "{$ROUTER_INTERNAL_SERVICE_PORT_UDP}" jump POLICY_MARK_GOTO_DEFAULT
  nft add rule $FAMILY $TABLE POLICY_VBOX_IPV4 ip daddr @DEFAULT_ROUTE_IPV4 tcp dport "{$ROUTER_INTERNAL_SERVICE_PORT_TCP}" jump POLICY_MARK_GOTO_DEFAULT
  nft add rule $FAMILY $TABLE POLICY_VBOX_IPV4 ip daddr @DEFAULT_ROUTE_IPV4 udp dport "{$ROUTER_INTERNAL_SERVICE_PORT_UDP}" jump POLICY_MARK_GOTO_DEFAULT

  # ipv4 skip package from outside
  nft add rule $FAMILY $TABLE POLICY_VBOX_IPV4 ip daddr @BLACKLIST_IPV4 jump POLICY_MARK_GOTO_DEFAULT
  nft add rule $FAMILY $TABLE POLICY_VBOX_IPV4 ip daddr @GEOIP_CN_IPV4 jump POLICY_MARK_GOTO_DEFAULT

  ### ipv4 - default goto tun
  nft add rule $FAMILY $TABLE POLICY_VBOX_IPV4 jump POLICY_MARK_GOTO_TUN
}

function vbox_iniitialize_rule_table_ipv6() {
  FAMILY="$1"
  TABLE="$2"

  nft list set $FAMILY $TABLE BLACKLIST_IPV6 >/dev/null 2>&1
  if [[ $? -ne 0 ]]; then
    nft add set $FAMILY $TABLE BLACKLIST_IPV6 '{ type ipv6_addr; }'
  fi
  nft list set $FAMILY $TABLE GEOIP_CN_IPV6 >/dev/null 2>&1
  if [[ $? -ne 0 ]]; then
    nft add set $FAMILY $TABLE GEOIP_CN_IPV6 '{ type ipv6_addr; flags interval; auto-merge; }'
  fi
  nft list set $FAMILY $TABLE LOCAL_IPV6 >/dev/null 2>&1
  if [[ $? -ne 0 ]]; then
    nft add set $FAMILY $TABLE LOCAL_IPV6 '{ type ipv6_addr; flags interval; auto-merge; }'
    nft add element $FAMILY $TABLE LOCAL_IPV6 '{::1/128, fc00::/7, fe80::/10}'
  fi
  nft list set $FAMILY $TABLE DEFAULT_ROUTE_IPV6 >/dev/null 2>&1
  if [[ $? -ne 0 ]]; then
    nft add set $FAMILY $TABLE DEFAULT_ROUTE_IPV6 '{ type ipv6_addr; flags interval; auto-merge ; }'
  fi

  # POLICY_VBOX_IPV6
  nft list chain $FAMILY $TABLE POLICY_VBOX_IPV6 >/dev/null 2>&1
  if [[ $? -ne 0 ]]; then
    nft add chain $FAMILY $TABLE POLICY_VBOX_IPV6
  fi
  nft flush chain $FAMILY $TABLE POLICY_VBOX_IPV6

  # ipv6 - local network
  nft add rule $FAMILY $TABLE POLICY_VBOX_IPV6 ip6 saddr @LOCAL_IPV6 ip6 daddr @LOCAL_IPV6 jump POLICY_MARK_GOTO_DEFAULT

  # ipv6 - DNAT or connect from outside
  nft add rule $FAMILY $TABLE POLICY_VBOX_IPV6 ip6 saddr @LOCAL_IPV6 tcp sport "{$ROUTER_INTERNAL_SERVICE_PORT_TCP}" jump POLICY_MARK_GOTO_DEFAULT
  nft add rule $FAMILY $TABLE POLICY_VBOX_IPV6 ip6 saddr @LOCAL_IPV6 udp sport "{$ROUTER_INTERNAL_SERVICE_PORT_UDP}" jump POLICY_MARK_GOTO_DEFAULT
  nft add rule $FAMILY $TABLE POLICY_VBOX_IPV6 ip6 saddr @DEFAULT_ROUTE_IPV6 tcp sport "{$ROUTER_INTERNAL_SERVICE_PORT_TCP}" jump POLICY_MARK_GOTO_DEFAULT
  nft add rule $FAMILY $TABLE POLICY_VBOX_IPV6 ip6 saddr @DEFAULT_ROUTE_IPV6 udp sport "{$ROUTER_INTERNAL_SERVICE_PORT_UDP}" jump POLICY_MARK_GOTO_DEFAULT
  nft add rule $FAMILY $TABLE POLICY_VBOX_IPV6 tcp dport "{$ROUTER_INTERNAL_DIRECTLY_VISIT_UDP_DPORT}" jump POLICY_MARK_GOTO_DEFAULT
  nft add rule $FAMILY $TABLE POLICY_VBOX_IPV6 udp dport "{$ROUTER_INTERNAL_DIRECTLY_VISIT_UDP_DPORT}" jump POLICY_MARK_GOTO_DEFAULT

  ### ipv6 - skip multicast
  nft add rule $FAMILY $TABLE POLICY_VBOX_IPV6 ip6 daddr '{ ff00::/8 }' jump POLICY_MARK_GOTO_DEFAULT

  ### ipv4 - skip private network and UDP of DNS
  nft add rule $FAMILY $TABLE POLICY_VBOX_IPV6 ip6 daddr @LOCAL_IPV6 tcp dport "{$ROUTER_INTERNAL_SERVICE_PORT_TCP}" jump POLICY_MARK_GOTO_DEFAULT
  nft add rule $FAMILY $TABLE POLICY_VBOX_IPV6 ip6 daddr @LOCAL_IPV6 udp dport "{$ROUTER_INTERNAL_SERVICE_PORT_UDP}" jump POLICY_MARK_GOTO_DEFAULT
  nft add rule $FAMILY $TABLE POLICY_VBOX_IPV6 ip6 daddr @DEFAULT_ROUTE_IPV6 tcp dport "{$ROUTER_INTERNAL_SERVICE_PORT_TCP}" jump POLICY_MARK_GOTO_DEFAULT
  nft add rule $FAMILY $TABLE POLICY_VBOX_IPV6 ip6 daddr @DEFAULT_ROUTE_IPV6 udp dport "{$ROUTER_INTERNAL_SERVICE_PORT_UDP}" jump POLICY_MARK_GOTO_DEFAULT

  # ipv4 skip package from outside
  nft add rule $FAMILY $TABLE POLICY_VBOX_IPV6 ip6 daddr @BLACKLIST_IPV6 jump POLICY_MARK_GOTO_DEFAULT
  nft add rule $FAMILY $TABLE POLICY_VBOX_IPV6 ip6 daddr @GEOIP_CN_IPV6 jump POLICY_MARK_GOTO_DEFAULT

  ### ipv6 - default goto tun
  nft add rule $FAMILY $TABLE POLICY_VBOX_IPV6 jump POLICY_MARK_GOTO_TUN
}

function vbox_iniitialize_rule_table() {
  FAMILY="$1"
  TABLE="$2"

  nft list table $FAMILY $TABLE >/dev/null 2>&1
  if [[ $? -ne 0 ]]; then
    nft add table $FAMILY $TABLE
  fi

  vbox_setup_rule_marks "$FAMILY" "$TABLE"
  vbox_iniitialize_rule_table_ipv4 "$FAMILY" "$TABLE"
  vbox_iniitialize_rule_table_ipv6 "$FAMILY" "$TABLE"

  # POLICY_VBOX_BOOTSTRAP
  nft list chain $FAMILY $TABLE POLICY_VBOX_BOOTSTRAP >/dev/null 2>&1
  if [[ $? -ne 0 ]]; then
    nft add chain $FAMILY $TABLE POLICY_VBOX_BOOTSTRAP
  fi
  nft flush chain $FAMILY $TABLE POLICY_VBOX_BOOTSTRAP

  nft add rule $FAMILY $TABLE POLICY_VBOX_BOOTSTRAP meta mark and 0x0f != 0x0 accept
  nft add rule $FAMILY $TABLE POLICY_VBOX_BOOTSTRAP ct mark and 0x0f != 0x0 meta mark set ct mark accept
  nft add rule $FAMILY $TABLE POLICY_VBOX_BOOTSTRAP meta mark and 0x0c == 0x0c jump POLICY_MARK_GOTO_DEFAULT

  ### skip internal services
  nft add rule $FAMILY $TABLE POLICY_VBOX_BOOTSTRAP meta l4proto != '{tcp, udp}' jump POLICY_MARK_GOTO_DEFAULT

  ## DNS always goto tun
  nft add rule $FAMILY $TABLE POLICY_VBOX_BOOTSTRAP udp dport '{53, 853}' jump POLICY_MARK_GOTO_TUN
  nft add rule $FAMILY $TABLE POLICY_VBOX_BOOTSTRAP tcp dport '{53, 853}' jump POLICY_MARK_GOTO_TUN

  ## skip black vlans
  if [[ ! -z "$SETUP_WITH_BLACKLIST_VLAN_IDS" ]]; then
    nft add rule $FAMILY $TABLE POLICY_VBOX_BOOTSTRAP vlan id "$SETUP_WITH_BLACKLIST_VLAN_IDS" jump POLICY_MARK_GOTO_DEFAULT
  fi

  nft add rule $FAMILY $TABLE POLICY_VBOX_BOOTSTRAP ip version 4 jump POLICY_VBOX_IPV4
  nft add rule $FAMILY $TABLE POLICY_VBOX_BOOTSTRAP ip6 version 6 jump POLICY_VBOX_IPV6
}

function vbox_setup_rule_chain() {
  FAMILY="$1"
  TABLE="$2"
  CHAIN="$3"

  shift
  shift
  shift

  nft list chain $FAMILY $TABLE $CHAIN >/dev/null 2>&1
  if [[ $? -ne 0 ]]; then
    nft add chain $FAMILY $TABLE $CHAIN "$@"
  fi
  nft flush chain $FAMILY $TABLE $CHAIN

  nft add rule $FAMILY $TABLE $CHAIN jump POLICY_VBOX_BOOTSTRAP
}

function vbox_remove_rule_marks() {
  FAMILY="$1"
  TABLE="$2"

  nft delete chain $FAMILY $TABLE POLICY_VBOX_BOOTSTRAP >/dev/null 2>&1
  nft delete chain $FAMILY $TABLE POLICY_VBOX_IPV4 >/dev/null 2>&1
  nft delete chain $FAMILY $TABLE POLICY_VBOX_IPV6 >/dev/null 2>&1
  nft delete chain $FAMILY $TABLE POLICY_MARK_GOTO_DEFAULT >/dev/null 2>&1
  nft delete chain $FAMILY $TABLE POLICY_MARK_GOTO_TUN >/dev/null 2>&1
}

if [ $VBOX_SETUP_IP_RULE_CLEAR -ne 0 ]; then
  vbox_iniitialize_rule_table inet vbox
  vbox_iniitialize_rule_table bridge vbox

  vbox_setup_rule_chain inet vbox PREROUTING '{ type filter hook prerouting priority filter + 1 ; }'
  vbox_setup_rule_chain inet vbox OUTPUT '{ type route hook output priority filter + 1 ; }'

  vbox_setup_rule_chain bridge vbox PREROUTING '{ type filter hook prerouting priority -280; }'

  ip -4 rule add nop priority $ROUTER_IP_RULE_GOTO_DEFAULT_PRIORITY
  ip -6 rule add nop priority $ROUTER_IP_RULE_GOTO_DEFAULT_PRIORITY
  ip -4 rule add fwmark 0x0c/0x0c goto $ROUTER_IP_RULE_GOTO_DEFAULT_PRIORITY priority $VBOX_SKIP_IP_RULE_PRIORITY
  ip -6 rule add fwmark 0x0c/0x0c goto $ROUTER_IP_RULE_GOTO_DEFAULT_PRIORITY priority $VBOX_SKIP_IP_RULE_PRIORITY

  # Update GEOIP
  if [[ ! -e "$VBOX_DATA_DIR/geoip-cn.json" ]]; then
    echo "$VBOX_DATA_DIR/geoip-cn.json not found"
    exit 1
  fi
  GEOIP_CN_ADDRESS_IPV4=($(jq '.rules[].ip_cidr[]' -r "$VBOX_DATA_DIR/geoip-cn.json" | grep -v ':'))
  GEOIP_CN_ADDRESS_IPV6=($(jq '.rules[].ip_cidr[]' -r "$VBOX_DATA_DIR/geoip-cn.json" | grep ':'))

  nft flush set inet vbox GEOIP_CN_IPV4
  nft flush set inet vbox GEOIP_CN_IPV6
  nft flush set bridge vbox GEOIP_CN_IPV4
  nft flush set bridge vbox GEOIP_CN_IPV6

  nft add element inet vbox GEOIP_CN_IPV4 "{$(echo "${GEOIP_CN_ADDRESS_IPV4[@]}" | sed 's;[[:space:]][[:space:]]*;,;g')}"
  nft add element bridge vbox GEOIP_CN_IPV4 " {$(echo "${GEOIP_CN_ADDRESS_IPV4[@]}" | sed 's;[[:space:]][[:space:]]*;,;g')}"
  nft add element inet vbox GEOIP_CN_IPV6 "{$(echo "${GEOIP_CN_ADDRESS_IPV6[@]}" | sed 's;[[:space:]][[:space:]]*;,;g')}"
  nft add element bridge vbox GEOIP_CN_IPV6 " {$(echo "${GEOIP_CN_ADDRESS_IPV6[@]}" | sed 's;[[:space:]][[:space:]]*;,;g')}"
else
  nft delete chain inet vbox PREROUTING >/dev/null 2>&1
  nft delete chain inet vbox OUTPUT >/dev/null 2>&1

  nft delete chain bridge vbox PREROUTING >/dev/null 2>&1

  vbox_remove_rule_marks inet vbox
  vbox_remove_rule_marks bridge vbox

  nft flush set inet vbox GEOIP_CN_IPV4
  nft flush set inet vbox GEOIP_CN_IPV6
  nft flush set bridge vbox GEOIP_CN_IPV4
  nft flush set bridge vbox GEOIP_CN_IPV6
fi
