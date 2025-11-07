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

DOCKER_EXEC=$((which podman > /dev/null 2>&1 && echo podman) || (which docker > /dev/null 2>&1 && echo docker))

if [[ -z "$VBOX_DATA_DIR" ]]; then
  VBOX_DATA_DIR="$HOME/vbox/data"
fi

if [[ -z "$VBOX_ETC_DIR" ]]; then
  VBOX_ETC_DIR="$HOME/vbox/etc"
fi

## ipv4绕过本地和私有网络地址:
## - 0.0.0.0/8 - 本网络地址
## - 10.0.0.0/8 - RFC 1918私有地址
## - 127.0.0.0/8 - 环回地址
## - 169.254.0.0/16 - 链路本地地址
## - 172.16.0.0/12 - RFC 1918私有地址
## - 192.0.0.0/24 - IETF协议分配
## - 192.0.2.0/24 - 测试网络1（以下地址集未排除）
## - 192.168.0.0/16 - RFC 1918私有地址
## - 198.18.0.0/15 - 网络互联测试 （以下地址集未排除）
## - 198.51.100.0/24 - 测试网络2（以下地址集未排除）
## - 203.0.113.0/24 - 测试网络3（以下地址集未排除）
## - 224.0.0.0/4 - 多播地址（224.0.0.0-239.255.255.255）
## - 240.0.0.0/4 - 保留地址
##   - 255.255.255.255/32 - 广播地址
IPV4_TUN_ADDRESS_SET=(
  1.0.0.0/8 2.0.0.0/7 4.0.0.0/6 8.0.0.0/7 11.0.0.0/8 12.0.0.0/6 16.0.0.0/4 32.0.0.0/3
  64.0.0.0/3 96.0.0.0/4 112.0.0.0/5 120.0.0.0/6 124.0.0.0/7 126.0.0.0/8 128.0.0.0/3
  160.0.0.0/5 168.0.0.0/8 169.0.0.0/9 169.128.0.0/10 169.192.0.0/11 169.224.0.0/12
  169.240.0.0/13 169.248.0.0/14 169.252.0.0/15 169.255.0.0/16 170.0.0.0/7
  172.0.0.0/12 172.32.0.0/11 172.64.0.0/10 172.128.0.0/9 173.0.0.0/8 174.0.0.0/7 176.0.0.0/4
  192.0.1.0/24 192.0.2.0/23 192.0.4.0/22 192.0.8.0/21 192.0.16.0/20 192.0.32.0/19 192.0.64.0/18 192.0.128.0/17 
  192.1.0.0/16 192.2.0.0/15 192.4.0.0/14 192.8.0.0/13 192.16.0.0/12 192.32.0.0/11 192.64.0.0/10
  192.128.0.0/11 192.160.0.0/13 192.169.0.0/16 192.170.0.0/15 192.172.0.0/14 192.176.0.0/12 192.192.0.0/10
  193.0.0.0/8 194.0.0.0/7 196.0.0.0/6 200.0.0.0/5 208.0.0.0/4
)

## ipv6绕过本地和私有网络地址:
## - ::1/128 - 环回地址
## - ::/128 - 未指定地址
## - ::ffff:0:0/96 - IPv4映射地址
## - 64:ff9b::/96 - IPv4/IPv6转换
## - 100::/64 - 丢弃前缀
## - fc00::/7 - 唯一本地地址
## - fe80::/10 - 链路本地地址
## - ff00::/8 - 多播地址
IPV6_TUN_ADDRESS_SET=(
  2000::/3
)

### 策略路由(占用mark的后4位,RPDB变化均会触发重路由, meta mark and 0xf != 0x0 都跳过重路由):
###   不需要重路由设置: meta mark and 0xf != 0x0
###   走 tun: 设置 fwmark = 0x3/0x3 (0011)
###   直接跳转到默认路由: 跳过 fwmark = 0xc/0xc (1100)
###     (vbox会设置511,0x1ff), 避开 meta mark and 0xf != 0x0 规则 (防止循环重定向)

if [[ -z "$ROUTER_IP_RULE_GOTO_DEFAULT_PRIORITY" ]]; then
  ROUTER_IP_RULE_GOTO_DEFAULT_PRIORITY=9091
fi

if [[ -z "$VBOX_SKIP_IP_RULE_PRIORITY" ]]; then
  VBOX_SKIP_IP_RULE_PRIORITY=8123
fi

if [[ -z "$VBOX_TUN_TABLE_ID" ]]; then
  VBOX_TUN_TABLE_ID=2022
fi

if [[ -z "$VBOX_TUN_WITH_SRC_TABLE_ID" ]]; then
  VBOX_TUN_WITH_SRC_TABLE_ID=$(($VBOX_TUN_TABLE_ID + 1))
fi

if [[ -z "$VBOX_TUN_PROXY_BLACKLIST_IFNAME" ]]; then
  VBOX_TUN_PROXY_BLACKLIST_IFNAME=()
fi

if [[ $ROUTER_NET_LOCAL_ENABLE_VBOX -ne 0 ]] && [[ "x$1" != "xclear" ]]; then
  VBOX_SETUP_IP_RULE_CLEAR=1
else
  VBOX_SETUP_IP_RULE_CLEAR=0
fi

function vbox_patch_configure() {
  if [[ -e "$VBOX_DATA_DIR/geoip-cn.json" ]] && [[ -e "$VBOX_DATA_DIR/geoip-cn.json.bak" ]]; then
    rm -f "$VBOX_DATA_DIR/geoip-cn.json.bak"
  fi
  if [[ -e "$VBOX_DATA_DIR/geoip-cn.json" ]]; then
    mv -f "$VBOX_DATA_DIR/geoip-cn.json" "$VBOX_DATA_DIR/geoip-cn.json.bak"
  fi

  $DOCKER_EXEC exec -it vbox-client vbox geoip export cn -f /usr/share/vbox/geoip.db -o /usr/share/vbox/geoip-cn.json
  $DOCKER_EXEC cp vbox-client:/usr/share/vbox/geoip-cn.json "$VBOX_DATA_DIR/geoip-cn.json" || mv -f "$VBOX_DATA_DIR/geoip-cn.json.bak" "$VBOX_DATA_DIR/geoip-cn.json"

  # 这里为了保持和 setup-client-pod-ip-rules 同行为
  PATCH_CONF_FILES=($(find "$VBOX_ETC_DIR" -maxdepth 1 -name "*.json.template"))
  mkdir -p "$SCRIPT_DIR/patch"
  if [ ${#PATCH_CONF_FILES[@]} -gt 0 ]; then
    for PATCH_CONF_FILE in "${PATCH_CONF_FILES[@]}"; do
      TARGET_CONF_FILE="$SCRIPT_DIR/patch/$(basename "$PATCH_CONF_FILE" | sed -E 's;.template$;;')"
      cp -f "$PATCH_CONF_FILE" "$TARGET_CONF_FILE"

      sed -i -E 's;(//[[:space:]]*)?"auto_redirect":[^,]+,;"auto_redirect": false,;g' "$TARGET_CONF_FILE"
      sed -i -E 's;(//[[:space:]]*)?"default_mark":([^,]+),;"default_mark":\2,;g' "$TARGET_CONF_FILE"
      sed -i -E 's;(//[[:space:]]*)?"routing_mark":([^,]+),;"routing_mark":\2,;g' "$TARGET_CONF_FILE"

      echo "Copy patched configure file: $TARGET_CONF_FILE to $VBOX_ETC_DIR/"
      cp -f "$TARGET_CONF_FILE" "$VBOX_ETC_DIR/"
    done
  fi
}

function vbox_get_last_tun_lookup_priority() {
  IP_FAMILY="$1"
  FIND_PROIRITY=""
  for ((i = 0; i < 10; i++)); do
    FIND_PROIRITY=$(ip $IP_FAMILY rule list | grep -E "\\blookup[[:space:]]+$VBOX_TUN_TABLE_ID\$" | tail -n 1 | awk 'BEGIN{FS=":"}{print $1}')
    if [[ ! -z "$FIND_PROIRITY" ]]; then
      break
    fi
    sleep 1
  done
  if [[ -z "$FIND_PROIRITY" ]]; then
    return 1
  fi

  echo "$FIND_PROIRITY"
}

function vbox_get_first_nop_lookup_priority_after_tun() {
  IP_FAMILY="$1"
  TUN_PRIORITY=$2
  FIND_PROIRITY=""
  if [[ -z "$TUN_PRIORITY" ]]; then
    for ((i = 0; i < 10; i++)); do
      FIND_PROIRITY=$(ip $IP_FAMILY rule show | grep -E '\bnop$' | tail -n 1 | awk 'BEGIN{FS=":"}{print $1}')
      if [[ ! -z "$FIND_PROIRITY" ]]; then
        break
      fi
      sleep 1
    done
  else
    for ((i = 0; i < 10; i++)); do
      FIND_PROIRITY=$(ip $IP_FAMILY rule show | grep -E '\bnop$' | awk "BEGIN{FS=\":\"} \$1>$TUN_PRIORITY {print \$1}" | head -n 1)
      if [[ ! -z "$FIND_PROIRITY" ]]; then
        break
      fi
      sleep 1
    done
  fi
  if [[ -z "$FIND_PROIRITY" ]]; then
    return 1
  fi

  echo "$FIND_PROIRITY"
}

function vbox_clear_ip_rules() {
  for IP_FAMILY in "$@"; do
    VBOX_IP_RULE_EXCLUDE_IF_PRIORITY=$(($VBOX_SKIP_IP_RULE_PRIORITY - 3))
    VBOX_IP_RULE_EXCLUDE_MARK_PRIORITY=$(($VBOX_SKIP_IP_RULE_PRIORITY - 2))
    VBOX_IP_RULE_INCLUDE_MARK_PRIORITY=$(($VBOX_SKIP_IP_RULE_PRIORITY - 1))
    VBOX_IP_RULE_NO_MARK_DEFAULT_ROUTE_PRIORITY=$VBOX_SKIP_IP_RULE_PRIORITY

    for CLEAR_PRIORITY in "$ROUTER_IP_RULE_GOTO_DEFAULT_PRIORITY" \
                          "$VBOX_IP_RULE_EXCLUDE_IF_PRIORITY" \
                          "$VBOX_IP_RULE_EXCLUDE_MARK_PRIORITY" \
                          "$VBOX_IP_RULE_INCLUDE_MARK_PRIORITY" \
                          "$VBOX_IP_RULE_NO_MARK_DEFAULT_ROUTE_PRIORITY"; do
      ROUTER_IP_RULE_LOOPUP_PRIORITY=$(ip $IP_FAMILY rule show priority $CLEAR_PRIORITY | awk 'END {print NF}')
      while [[ 0 -ne $ROUTER_IP_RULE_LOOPUP_PRIORITY ]]; do
        ip $IP_FAMILY rule delete priority $CLEAR_PRIORITY
        ROUTER_IP_RULE_LOOPUP_PRIORITY=$(ip $IP_FAMILY rule show priority $CLEAR_PRIORITY | awk 'END {print NF}')
      done
    done

    # clear ip route table
    TABLE_RULE_COUNT=$(ip $IP_FAMILY route show table $VBOX_TUN_WITH_SRC_TABLE_ID 2>/dev/null | wc -l)
    if [[ $TABLE_RULE_COUNT -gt 0 ]]; then
      ip $IP_FAMILY route flush table $VBOX_TUN_WITH_SRC_TABLE_ID
    fi
  done
}

function vbox_setup_ip_rules() {
  VBOX_IP_RULE_EXCLUDE_IF_PRIORITY=$(($VBOX_SKIP_IP_RULE_PRIORITY - 3))
  VBOX_IP_RULE_EXCLUDE_MARK_PRIORITY=$(($VBOX_SKIP_IP_RULE_PRIORITY - 2))
  VBOX_IP_RULE_INCLUDE_MARK_PRIORITY=$(($VBOX_SKIP_IP_RULE_PRIORITY - 1))
  VBOX_IP_RULE_NO_MARK_DEFAULT_ROUTE_PRIORITY=$VBOX_SKIP_IP_RULE_PRIORITY
  for IP_FAMILY in "$@"; do
    LAST_TUN_LOOKUP_PRIORITY=$(vbox_get_last_tun_lookup_priority "$IP_FAMILY")
    NOP_LOOKUP_PRIORITY=$(vbox_get_first_nop_lookup_priority_after_tun "$IP_FAMILY" "$LAST_TUN_LOOKUP_PRIORITY")

    if [[ -z "$NOP_LOOKUP_PRIORITY" ]]; then
      ip $IP_FAMILY rule add nop priority $ROUTER_IP_RULE_GOTO_DEFAULT_PRIORITY
      NOP_LOOKUP_PRIORITY=$ROUTER_IP_RULE_GOTO_DEFAULT_PRIORITY
    fi

    # Exclude interfaces
    if [[ -z "$VBOX_TUN_INTERFACE" ]]; then
      DETECT_TUN_IF_NAME_FROM_IP_ROUTE_TABLE="$(ip $IP_FAMILY route show table $VBOX_TUN_TABLE_ID 2>/dev/null | grep -E -o 'dev[[:space:]]+[^[:space:]]+' | awk '{print $NF}')"
      if [[ ! -z "$DETECT_TUN_IF_NAME_FROM_IP_ROUTE_TABLE" ]]; then
        DETECT_TUN_IF_NAMES=("$DETECT_TUN_IF_NAME_FROM_IP_ROUTE_TABLE")
      else
        DETECT_TUN_IF_NAMES=($(nmcli --fields NAME,TYPE connection show | awk '{if($2=="tun"){print $1}}'))
      fi
      if [[ ${#DETECT_TUN_IF_NAMES[@]} -gt 0 ]]; then
        for TUN_IF_NAME in "${DETECT_TUN_IF_NAMES[@]}"; do
          ip link show "$TUN_IF_NAME" >/dev/null 2>&1 && \
            ip $IP_FAMILY rule add iif "$TUN_IF_NAME" goto $NOP_LOOKUP_PRIORITY priority $VBOX_IP_RULE_EXCLUDE_IF_PRIORITY && \
            VBOX_TUN_INTERFACE="$TUN_IF_NAME"
        done
      else
        ip link show "tun0" >/dev/null 2>&1 && \
          ip $IP_FAMILY rule add iif "tun0" goto $NOP_LOOKUP_PRIORITY priority $VBOX_IP_RULE_EXCLUDE_IF_PRIORITY
        VBOX_TUN_INTERFACE=tun0
      fi
    else
      ip link show "$VBOX_TUN_INTERFACE" >/dev/null 2>&1 && \
        ip $IP_FAMILY rule add iif "$VBOX_TUN_INTERFACE" goto $NOP_LOOKUP_PRIORITY priority $VBOX_IP_RULE_EXCLUDE_IF_PRIORITY
    fi
    if [[ ${#VBOX_TUN_PROXY_BLACKLIST_IFNAME[@]} -gt 0 ]]; then
      for IGNORE_IFNAME in "${VBOX_TUN_PROXY_BLACKLIST_IFNAME[@]}"; do
        if [[ ! -z "$VBOX_TUN_INTERFACE" ]] && [[ "$VBOX_TUN_INTERFACE" == "$IGNORE_IFNAME" ]]; then
          continue
        fi
        ip link show "$IGNORE_IFNAME" >/dev/null 2>&1 && \
          ip $IP_FAMILY rule add iif "$IGNORE_IFNAME" goto $NOP_LOOKUP_PRIORITY priority $VBOX_IP_RULE_EXCLUDE_IF_PRIORITY
      done
    fi

    # Exclude marks
    ip $IP_FAMILY rule add fwmark 0xc/0xc goto $NOP_LOOKUP_PRIORITY priority $VBOX_IP_RULE_EXCLUDE_MARK_PRIORITY
    
    # Include marks, 指定 src ip。否则无法触发重路由
    # 对比测试指令: ip route get 74.125.195.113 from $PPP_IP mark 3 和 ip route get 74.125.195.113 mark 3
    VBOX_TUN_ORIGIN_TABLE_RULE=($(ip $IP_FAMILY route show table $VBOX_TUN_TABLE_ID | tail -n 1 | awk '{$1="";print $0}' | grep -E -o '.*dev[[:space:]]+[^[:space:]]+'))
    ip $IP_FAMILY route flush table $VBOX_TUN_WITH_SRC_TABLE_ID
    if [[ ! -z "IP_FAMILY" ]] && [[ "$IP_FAMILY" == "-6" ]]; then
      VBOX_TUN_IP_ADDR=""
      for ((i = 0; i < 10; i++)); do
        VBOX_TUN_IP_ADDR=$(ip -o $IP_FAMILY addr show dev $VBOX_TUN_INTERFACE scope global | awk 'match($0, /inet6\s+([0-9a-fA-F:]+)/, ip) { print ip[1] }' | head -n 1)
        if [[ ! -z "$VBOX_TUN_IP_ADDR" ]]; then
          break
        fi
        sleep 1
      done
      for ROUTE_CIDR in "${IPV6_TUN_ADDRESS_SET[@]}"; do
        ip $IP_FAMILY route add "$ROUTE_CIDR" "dev" "$VBOX_TUN_INTERFACE" src "$VBOX_TUN_IP_ADDR" table $VBOX_TUN_WITH_SRC_TABLE_ID
      done
    else
      VBOX_TUN_IP_ADDR=""
      for ((i = 0; i < 10; i++)); do
        VBOX_TUN_IP_ADDR=$(ip -o $IP_FAMILY addr show dev $VBOX_TUN_INTERFACE scope global | awk 'match($0, /inet\s+([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)/, ip) { print ip[1] }' | head -n 1)
        if [[ ! -z "$VBOX_TUN_IP_ADDR" ]]; then
          break
        fi
        sleep 1
      done
      for ROUTE_CIDR in "${IPV4_TUN_ADDRESS_SET[@]}"; do
        ip $IP_FAMILY route add "$ROUTE_CIDR" "${VBOX_TUN_ORIGIN_TABLE_RULE[@]}" src "$VBOX_TUN_IP_ADDR" table $VBOX_TUN_WITH_SRC_TABLE_ID
      done
    fi
    ip $IP_FAMILY rule add fwmark 0x3/0x3 lookup $VBOX_TUN_WITH_SRC_TABLE_ID priority $VBOX_IP_RULE_INCLUDE_MARK_PRIORITY

    # NO mark to default route, 自动生成的ppp0没有指定src，触发重路由会导致ip不正确。所以默认路由还是指向原本的默认路由
    ip $IP_FAMILY rule add fwmark 0x0/0xf goto $NOP_LOOKUP_PRIORITY priority $VBOX_IP_RULE_NO_MARK_DEFAULT_ROUTE_PRIORITY
  done
}

function vbox_setup_rule_marks() {
  FAMILY="$1"
  TABLE="$2"

  # POLICY_MARK_GOTO_DEFAULT
  nft list chain $FAMILY $TABLE POLICY_MARK_GOTO_DEFAULT >/dev/null 2>&1
  if [[ $? -ne 0 ]]; then
    nft add chain $FAMILY $TABLE POLICY_MARK_GOTO_DEFAULT
  fi
  nft flush chain $FAMILY $TABLE POLICY_MARK_GOTO_DEFAULT
  nft add rule $FAMILY $TABLE POLICY_MARK_GOTO_DEFAULT meta mark set meta mark and 0xfffffff0 xor 0xc
  nft add rule $FAMILY $TABLE POLICY_MARK_GOTO_DEFAULT ct mark set meta mark accept

  # POLICY_MARK_GOTO_TUN
  nft list chain $FAMILY $TABLE POLICY_MARK_GOTO_TUN >/dev/null 2>&1
  if [[ $? -ne 0 ]]; then
    nft add chain $FAMILY $TABLE POLICY_MARK_GOTO_TUN
  fi
  nft flush chain $FAMILY $TABLE POLICY_MARK_GOTO_TUN
  nft add rule $FAMILY $TABLE POLICY_MARK_GOTO_TUN meta mark set meta mark and 0xfffffff0 xor 0x3
  nft add rule $FAMILY $TABLE POLICY_MARK_GOTO_TUN ct mark set meta mark accept
}

function vbox_iniitialize_rule_table_inet() {
  FAMILY="$1"
  TABLE="$2"

  # Ports
  nft list set $FAMILY $TABLE LOCAL_SERVICE_PORT_UDP >/dev/null 2>&1
  if [[ $? -ne 0 ]]; then
    nft add set $FAMILY $TABLE LOCAL_SERVICE_PORT_UDP '{ type inet_service; flags interval; auto-merge; }'
    nft add element $FAMILY $TABLE LOCAL_SERVICE_PORT_UDP "{$ROUTER_INTERNAL_SERVICE_PORT_UDP}"

    if [[ ! -z "$ROUTER_INTERNAL_DIRECTLY_VISIT_UDP_DPORT" ]]; then
      nft add element $FAMILY $TABLE LOCAL_SERVICE_PORT_UDP "{$ROUTER_INTERNAL_DIRECTLY_VISIT_UDP_DPORT}"
    fi
  fi
  nft list set $FAMILY $TABLE LOCAL_SERVICE_PORT_TCP >/dev/null 2>&1
  if [[ $? -ne 0 ]]; then
    nft add set $FAMILY $TABLE LOCAL_SERVICE_PORT_TCP '{ type inet_service; flags interval; auto-merge; }'
    nft add element $FAMILY $TABLE LOCAL_SERVICE_PORT_TCP "{$ROUTER_INTERNAL_SERVICE_PORT_TCP}"
  fi
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
    nft add element $FAMILY $TABLE LOCAL_IPV4 '{0.0.0.0/8, 10.0.0.0/8, 127.0.0.0/8, 169.254.0.0/16, 172.16.0.0/12, 192.0.0.0/24, 192.168.0.0/16, 224.0.0.0/4, 240.0.0.0/4}'
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

  ## DNS always goto tun
  nft add rule $FAMILY $TABLE POLICY_VBOX_IPV4 ip daddr != @LOCAL_IPV4 udp dport '{53, 784, 853, 8853}' jump POLICY_MARK_GOTO_TUN
  nft add rule $FAMILY $TABLE POLICY_VBOX_IPV4 ip daddr != @LOCAL_IPV4 tcp dport '{53, 784, 853, 8853}' jump POLICY_MARK_GOTO_TUN

  # ipv4 - DNAT or connect from outside
  nft add rule $FAMILY $TABLE POLICY_VBOX_IPV4 ip saddr @LOCAL_IPV4 tcp sport "@LOCAL_SERVICE_PORT_TCP" jump POLICY_MARK_GOTO_DEFAULT
  nft add rule $FAMILY $TABLE POLICY_VBOX_IPV4 ip saddr @LOCAL_IPV4 udp sport "@LOCAL_SERVICE_PORT_UDP" jump POLICY_MARK_GOTO_DEFAULT
  nft add rule $FAMILY $TABLE POLICY_VBOX_IPV4 ip saddr @DEFAULT_ROUTE_IPV4 tcp sport "@LOCAL_SERVICE_PORT_TCP" jump POLICY_MARK_GOTO_DEFAULT
  nft add rule $FAMILY $TABLE POLICY_VBOX_IPV4 ip saddr @DEFAULT_ROUTE_IPV4 udp sport "@LOCAL_SERVICE_PORT_UDP" jump POLICY_MARK_GOTO_DEFAULT

  ### ipv4 - skip link-local and broadcast address, 172.20.1.1/24 is used for remote debug
  nft add rule $FAMILY $TABLE POLICY_VBOX_IPV4 ip daddr {224.0.0.0/4, 255.255.255.255/32, 172.20.1.1/24} jump POLICY_MARK_GOTO_DEFAULT

  ### ipv4 - skip private network and UDP of DNS
  nft add rule $FAMILY $TABLE POLICY_VBOX_IPV4 ip daddr @LOCAL_IPV4 tcp dport "@LOCAL_SERVICE_PORT_TCP" jump POLICY_MARK_GOTO_DEFAULT
  nft add rule $FAMILY $TABLE POLICY_VBOX_IPV4 ip daddr @LOCAL_IPV4 udp dport "@LOCAL_SERVICE_PORT_UDP" jump POLICY_MARK_GOTO_DEFAULT
  nft add rule $FAMILY $TABLE POLICY_VBOX_IPV4 ip daddr @DEFAULT_ROUTE_IPV4 tcp dport "@LOCAL_SERVICE_PORT_TCP" jump POLICY_MARK_GOTO_DEFAULT
  nft add rule $FAMILY $TABLE POLICY_VBOX_IPV4 ip daddr @DEFAULT_ROUTE_IPV4 udp dport "@LOCAL_SERVICE_PORT_UDP" jump POLICY_MARK_GOTO_DEFAULT

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
    nft add element $FAMILY $TABLE LOCAL_IPV6 '{::1/128, ::/128, ::ffff:0:0/96, 64:ff9b::/96, 100::/64, fc00::/7, fe80::/10, ff00::/8}'
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

  ## DNS always goto tun
  nft add rule $FAMILY $TABLE POLICY_VBOX_IPV6 ip6 daddr != @LOCAL_IPV6 udp dport '{53, 784, 853, 8853}' jump POLICY_MARK_GOTO_TUN
  nft add rule $FAMILY $TABLE POLICY_VBOX_IPV6 ip6 daddr != @LOCAL_IPV6 tcp dport '{53, 784, 853, 8853}' jump POLICY_MARK_GOTO_TUN

  # ipv6 - DNAT or connect from outside
  nft add rule $FAMILY $TABLE POLICY_VBOX_IPV6 ip6 saddr @LOCAL_IPV6 tcp sport "@LOCAL_SERVICE_PORT_TCP" jump POLICY_MARK_GOTO_DEFAULT
  nft add rule $FAMILY $TABLE POLICY_VBOX_IPV6 ip6 saddr @LOCAL_IPV6 udp sport "@LOCAL_SERVICE_PORT_UDP" jump POLICY_MARK_GOTO_DEFAULT
  nft add rule $FAMILY $TABLE POLICY_VBOX_IPV6 ip6 saddr @DEFAULT_ROUTE_IPV6 tcp sport "@LOCAL_SERVICE_PORT_TCP" jump POLICY_MARK_GOTO_DEFAULT
  nft add rule $FAMILY $TABLE POLICY_VBOX_IPV6 ip6 saddr @DEFAULT_ROUTE_IPV6 udp sport "@LOCAL_SERVICE_PORT_UDP" jump POLICY_MARK_GOTO_DEFAULT

  ### ipv4 - skip private network and UDP of DNS
  nft add rule $FAMILY $TABLE POLICY_VBOX_IPV6 ip6 daddr @LOCAL_IPV6 tcp dport "@LOCAL_SERVICE_PORT_TCP" jump POLICY_MARK_GOTO_DEFAULT
  nft add rule $FAMILY $TABLE POLICY_VBOX_IPV6 ip6 daddr @LOCAL_IPV6 udp dport "@LOCAL_SERVICE_PORT_UDP" jump POLICY_MARK_GOTO_DEFAULT
  nft add rule $FAMILY $TABLE POLICY_VBOX_IPV6 ip6 daddr @DEFAULT_ROUTE_IPV6 tcp dport "@LOCAL_SERVICE_PORT_TCP" jump POLICY_MARK_GOTO_DEFAULT
  nft add rule $FAMILY $TABLE POLICY_VBOX_IPV6 ip6 daddr @DEFAULT_ROUTE_IPV6 udp dport "@LOCAL_SERVICE_PORT_UDP" jump POLICY_MARK_GOTO_DEFAULT

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
  vbox_iniitialize_rule_table_inet "$FAMILY" "$TABLE"
  vbox_iniitialize_rule_table_ipv4 "$FAMILY" "$TABLE"
  vbox_iniitialize_rule_table_ipv6 "$FAMILY" "$TABLE"

  # POLICY_VBOX_BOOTSTRAP
  nft list chain $FAMILY $TABLE POLICY_VBOX_BOOTSTRAP >/dev/null 2>&1
  if [[ $? -ne 0 ]]; then
    nft add chain $FAMILY $TABLE POLICY_VBOX_BOOTSTRAP
  fi
  nft flush chain $FAMILY $TABLE POLICY_VBOX_BOOTSTRAP

  nft add rule $FAMILY $TABLE POLICY_VBOX_BOOTSTRAP meta mark and 0xf != 0x0 ct mark and 0xf == 0x0 ct mark set meta mark accept
  nft add rule $FAMILY $TABLE POLICY_VBOX_BOOTSTRAP meta mark and 0xf != 0x0 accept
  nft add rule $FAMILY $TABLE POLICY_VBOX_BOOTSTRAP ct mark and 0xf != 0x0 meta mark set ct mark accept
  nft add rule $FAMILY $TABLE POLICY_VBOX_BOOTSTRAP meta mark and 0xc == 0xc jump POLICY_MARK_GOTO_DEFAULT

  ### skip internal services
  nft add rule $FAMILY $TABLE POLICY_VBOX_BOOTSTRAP meta l4proto != '{tcp, udp}' jump POLICY_MARK_GOTO_DEFAULT

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

function vbox_update_geoip() {
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

  GEOIP_CN_ADDRESS_COUNT=${#GEOIP_CN_ADDRESS_IPV4[@]}
  GEOIP_CN_ADDRESS_START=0
  while [[ $GEOIP_CN_ADDRESS_START -lt $GEOIP_CN_ADDRESS_COUNT ]]; do
    GEOIP_CN_ADDRESS_END=$(($GEOIP_CN_ADDRESS_START + 2000))
    if [[ $GEOIP_CN_ADDRESS_END -lt $GEOIP_CN_ADDRESS_COUNT ]]; then
      nft add element inet vbox GEOIP_CN_IPV4 "{$(echo "${GEOIP_CN_ADDRESS_IPV4[@]:$GEOIP_CN_ADDRESS_START:2000}" | sed 's;[[:space:]][[:space:]]*;,;g')}"
      nft add element bridge vbox GEOIP_CN_IPV4 "{$(echo "${GEOIP_CN_ADDRESS_IPV4[@]:$GEOIP_CN_ADDRESS_START:2000}" | sed 's;[[:space:]][[:space:]]*;,;g')}"
      GEOIP_CN_ADDRESS_START=$GEOIP_CN_ADDRESS_END
    else
      GEOIP_CN_ADDRESS_OFFSET=$(($GEOIP_CN_ADDRESS_COUNT - $GEOIP_CN_ADDRESS_START))
      nft add element inet vbox GEOIP_CN_IPV4 "{$(echo "${GEOIP_CN_ADDRESS_IPV4[@]:$GEOIP_CN_ADDRESS_START:$GEOIP_CN_ADDRESS_OFFSET}" | sed 's;[[:space:]][[:space:]]*;,;g')}"
      nft add element bridge vbox GEOIP_CN_IPV4 "{$(echo "${GEOIP_CN_ADDRESS_IPV4[@]:$GEOIP_CN_ADDRESS_START:$GEOIP_CN_ADDRESS_OFFSET}" | sed 's;[[:space:]][[:space:]]*;,;g')}"
      GEOIP_CN_ADDRESS_START=$GEOIP_CN_ADDRESS_COUNT
    fi
  done

  GEOIP_CN_ADDRESS_COUNT=${#GEOIP_CN_ADDRESS_IPV6[@]}
  GEOIP_CN_ADDRESS_START=0
  while [[ $GEOIP_CN_ADDRESS_START -lt $GEOIP_CN_ADDRESS_COUNT ]]; do
    GEOIP_CN_ADDRESS_END=$(($GEOIP_CN_ADDRESS_START + 2000))
    if [[ $GEOIP_CN_ADDRESS_END -lt $GEOIP_CN_ADDRESS_COUNT ]]; then
      nft add element inet vbox GEOIP_CN_IPV6 "{$(echo "${GEOIP_CN_ADDRESS_IPV6[@]:$GEOIP_CN_ADDRESS_START:2000}" | sed 's;[[:space:]][[:space:]]*;,;g')}"
      nft add element bridge vbox GEOIP_CN_IPV6 "{$(echo "${GEOIP_CN_ADDRESS_IPV6[@]:$GEOIP_CN_ADDRESS_START:2000}" | sed 's;[[:space:]][[:space:]]*;,;g')}"
      GEOIP_CN_ADDRESS_START=$GEOIP_CN_ADDRESS_END
    else
      GEOIP_CN_ADDRESS_OFFSET=$(($GEOIP_CN_ADDRESS_COUNT - $GEOIP_CN_ADDRESS_START))
      nft add element inet vbox GEOIP_CN_IPV6 "{$(echo "${GEOIP_CN_ADDRESS_IPV6[@]:$GEOIP_CN_ADDRESS_START:$GEOIP_CN_ADDRESS_OFFSET}" | sed 's;[[:space:]][[:space:]]*;,;g')}"
      nft add element bridge vbox GEOIP_CN_IPV6 "{$(echo "${GEOIP_CN_ADDRESS_IPV6[@]:$GEOIP_CN_ADDRESS_START:$GEOIP_CN_ADDRESS_OFFSET}" | sed 's;[[:space:]][[:space:]]*;,;g')}"
      GEOIP_CN_ADDRESS_START=$GEOIP_CN_ADDRESS_COUNT
    fi
  done
}

if [ $VBOX_SETUP_IP_RULE_CLEAR -ne 0 ]; then
  vbox_patch_configure
  vbox_clear_ip_rules "-4" "-6"
  vbox_iniitialize_rule_table inet vbox
  vbox_iniitialize_rule_table bridge vbox

  vbox_setup_rule_chain inet vbox PREROUTING '{ type filter hook prerouting priority dstnat - 1 ; }'
  # 必须在高优先级（mangle）打标记，否则无法影响重路由
  vbox_setup_rule_chain inet vbox OUTPUT '{ type route hook output priority mangle - 1 ; }'

  vbox_setup_rule_chain bridge vbox PREROUTING '{ type filter hook prerouting priority -280; }'

  # Sing-box has poor performance, we setup ip rules ourself
  vbox_setup_ip_rules "-4" "-6"

  vbox_update_geoip

  # clear DNS server cache
  # su tools -l -c 'env XDG_RUNTIME_DIR="/run/user/$UID" DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR}/bus" systemctl --user restart container-adguard-home'

else
  vbox_clear_ip_rules "-4" "-6"

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

