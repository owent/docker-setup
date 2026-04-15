#!/bin/bash

# $ROUTER_HOME/sdwan/setup-sdwan-route.sh
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

if command -v podman >/dev/null 2>&1; then
  DOCKER_EXEC=podman
elif command -v docker >/dev/null 2>&1; then
  DOCKER_EXEC=docker
else
  DOCKER_EXEC=""
fi

if [[ -z "$SDWAN_DATA_DIR" ]]; then
  SDWAN_DATA_DIR="$SCRIPT_DIR/data"
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
## - (额外备注): 运营商内网（CGNAT）地址: 100.64.0.0/10 (100.64.0.0 - 100.127.255.255)
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
IPV4_TUN_ADDRESS_THROW=( )

## ipv6绕过本地和私有网络地址:
## - ::1/128 - 环回地址
## - ::/128 - 未指定地址
## - ::ffff:0:0/96 - IPv4映射地址
## - 64:ff9b::/96 - IPv4/IPv6转换
## - 100::/64 - 丢弃前缀
## - 2001::/32 - Teredo隧道(需要绕过)
## - 2002::/16 - 6to4 隧道(需要绕过)
## - 2001:db8::/32 - 文档前缀（建议绕过）
## - fc00::/7 - 唯一本地地址
## - fe80::/10 - 链路本地地址
## - ff00::/8 - 多播地址
IPV6_TUN_ADDRESS_SET=(
  2000::/3
)
IPV6_TUN_ADDRESS_THROW=(
  2001::/32
  2001:db8::/32
  2002::/16
)

### 策略路由(占用mark的后4位,RPDB变化均会触发重路由, meta mark and 0xf != 0x0 都跳过重路由):
###   不需要重路由设置: meta mark and 0xf0 != 0x0
###   走 sdwan: 设置 fwmark = 0x10/0xf0
###   走 sdwan: 设置 fwmark = 0x20/0xf0
###   直接跳转到默认路由: 跳过 fwmark = 0xe0/0xf0
###     避开 meta mark and 0xf0 != 0x0 规则 (防止循环重定向)

if [[ -z "$ROUTER_IP_RULE_GOTO_DEFAULT_PRIORITY" ]]; then
  ROUTER_IP_RULE_GOTO_DEFAULT_PRIORITY=19091
fi

if [[ -z "$SDWAN_SKIP_IP_RULE_PRIORITY" ]]; then
  SDWAN_SKIP_IP_RULE_PRIORITY=8023
fi

if [[ -z "$SDWAN_TUN_TABLE_ID" ]]; then
  SDWAN_TUN_TABLE_ID=2026
fi

# 设置路由规则和interface
SDWAN_TUN_CHANNELS=(
  "FAST"
  "AI"
)
SDWAN_TUN_INTERFACE_FAST="sdwan-hk1"
SDWAN_TUN_INTERFACE_AI="sdwan-hk1"

SDWAN_TUN_CHANNEL_TABLE_ID_START=$(($SDWAN_TUN_TABLE_ID - 99 - ${#SDWAN_TUN_CHANNELS[@]}))
for SDWAN_TUN_CHANNEL in "${SDWAN_TUN_CHANNELS[@]}"; do
  SDWAN_TUN_CHANNEL_INTERFACE_VAR="SDWAN_TUN_INTERFACE_${SDWAN_TUN_CHANNEL}"
  if [[ -z "${!SDWAN_TUN_CHANNEL_INTERFACE_VAR}" ]]; then
    printf -v "$SDWAN_TUN_CHANNEL_INTERFACE_VAR" '%s' ""
  fi

  SDWAN_TUN_CHANNEL_TABLE_ID_VAR="SDWAN_TUN_PROXY_WHITELIST_TABLE_ID_${SDWAN_TUN_CHANNEL}"
  if [[ -z "${!SDWAN_TUN_CHANNEL_TABLE_ID_VAR}" ]]; then
    printf -v "$SDWAN_TUN_CHANNEL_TABLE_ID_VAR" '%s' "$SDWAN_TUN_CHANNEL_TABLE_ID_START"
  fi
  SDWAN_TUN_CHANNEL_TABLE_ID_START=$(($SDWAN_TUN_CHANNEL_TABLE_ID_START + 1))
done

if [[ -z "$SDWAN_TUN_PROXY_BLACKLIST_IFNAME" ]]; then
  SDWAN_TUN_PROXY_BLACKLIST_IFNAME=()
fi

if [[ -z "$SDWAN_WAIT_READY_RETRY" ]]; then
  SDWAN_WAIT_READY_RETRY=30
fi

# 如果接口不支持转发，尝试走NAT
if [[ -z "$SDWAN_SNAT_TO_INTERFACE_IP" ]]; then
  SDWAN_SNAT_TO_INTERFACE_IP=0
fi

if [[ $ROUTER_NET_LOCAL_ENABLE_SDWAN -ne 0 ]] && [[ "x$1" != "xclear" ]]; then
  SDWAN_SETUP_IP_RULE_CLEAR=0
else
  SDWAN_SETUP_IP_RULE_CLEAR=1
fi

function sdwan_get_channel_table_id() {
  SDWAN_TUN_CHANNEL="$1"
  SDWAN_TUN_PROXY_CHANNEL_TABLE_ID_VAR="SDWAN_TUN_PROXY_WHITELIST_TABLE_ID_${SDWAN_TUN_CHANNEL}"
  printf '%s\n' "${!SDWAN_TUN_PROXY_CHANNEL_TABLE_ID_VAR}"
}

function sdwan_get_channel_configured_interface() {
  SDWAN_TUN_CHANNEL="$1"
  SDWAN_TUN_CHANNEL_INTERFACE_VAR="SDWAN_TUN_INTERFACE_${SDWAN_TUN_CHANNEL}"
  printf '%s\n' "${!SDWAN_TUN_CHANNEL_INTERFACE_VAR}"
}

function sdwan_wait_for_interface() {
  INTERFACE_NAME="$1"
  WAIT_RETRY_COUNT="${2:-$SDWAN_WAIT_READY_RETRY}"

  if [[ -z "$INTERFACE_NAME" ]]; then
    return 1
  fi

  for ((i = 0; i < WAIT_RETRY_COUNT; i++)); do
    if ip link show dev "$INTERFACE_NAME" >/dev/null 2>&1; then
      printf '%s\n' "$INTERFACE_NAME"
      return 0
    fi
    sleep 1
  done

  return 1
}

function sdwan_wait_for_interface_address() {
  IP_FAMILY="$1"
  INTERFACE_NAME="$2"
  WAIT_RETRY_COUNT="${3:-$SDWAN_WAIT_READY_RETRY}"
  INTERFACE_ADDRESS=""

  if [[ -z "$INTERFACE_NAME" ]]; then
    return 1
  fi

  for ((i = 0; i < WAIT_RETRY_COUNT; i++)); do
    if ! ip link show dev "$INTERFACE_NAME" >/dev/null 2>&1; then
      sleep 1
      continue
    fi

    if [[ "$IP_FAMILY" == "-6" ]]; then
      INTERFACE_ADDRESS=$(ip -o $IP_FAMILY addr show dev "$INTERFACE_NAME" scope global | awk 'match($0, /inet6\s+([0-9a-fA-F:]+)/, ip) { print ip[1] }' | head -n 1)
    else
      INTERFACE_ADDRESS=$(ip -o $IP_FAMILY addr show dev "$INTERFACE_NAME" scope global | awk 'match($0, /inet\s+([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)/, ip) { print ip[1] }' | head -n 1)
    fi

    if [[ -n "$INTERFACE_ADDRESS" ]]; then
      printf '%s\n' "$INTERFACE_ADDRESS"
      return 0
    fi

    # Ignore ipv6 when ipv4 is available, because some ISP's ipv6 deployment is not stable yet, and ipv6 route setup failure will cause all traffic loss if both ipv4 and ipv6 rules exist at the same time.
    if [[ "$IP_FAMILY" == "-6" ]]; then
      INTERFACE_ADDRESS=$(ip -o -4 addr show dev "$INTERFACE_NAME" scope global | awk 'match($0, /inet\s+([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)/, ip) { print ip[1] }' | head -n 1)
      if [[ -n "$INTERFACE_ADDRESS" ]]; then
        return 0
      fi
    fi

    sleep 1
  done

  return 1
}

function sdwan_flush_route_table_if_exists() {
  IP_FAMILY="$1"
  TABLE_ID="$2"
  TABLE_RULES=$(ip $IP_FAMILY route show table "$TABLE_ID" 2>/dev/null)

  if [[ -n "$TABLE_RULES" ]]; then
    ip $IP_FAMILY route flush table "$TABLE_ID" >/dev/null 2>&1 || true
  fi
}

function sdwan_remove_snat_table() {
  FAMILY="$1"
  TABLE="$2"
  shift 2
  
  nft delete chain $FAMILY $TABLE POSTROUTING >/dev/null 2>&1 || true
}

function sdwan_setup_snat_table() {
  FAMILY="$1"
  TABLE="$2"
  shift 2

  if [[ $SDWAN_SNAT_TO_INTERFACE_IP -eq 0 ]]; then
    sdwan_remove_snat_table "$FAMILY" "$TABLE" "$@"
    return 0
  fi

  for IP_FAMILY in "$@"; do
    if [[ "$IP_FAMILY" == "-6" ]] && [[ $NAT_SETUP_SKIP_IPV6 -ne 0 ]]; then
      continue
    fi

    if ! nft list table $FAMILY $TABLE >/dev/null 2>&1; then
      nft add table $FAMILY $TABLE
    fi

    if ! nft list chain $FAMILY $TABLE POSTROUTING >/dev/null 2>&1; then
      nft add chain $FAMILY $TABLE POSTROUTING "{ type nat hook postrouting priority srcnat - 10; policy accept; }"
    fi

    nft flush chain $FAMILY $TABLE POSTROUTING

    SDWAN_TUN_CHANNEL_MARK=0
    for SDWAN_TUN_CHANNEL in "${SDWAN_TUN_CHANNELS[@]}"; do
      SDWAN_TUN_CHANNEL_MARK=$(($SDWAN_TUN_CHANNEL_MARK + 0x10))
      SDWAN_TUN_CHANNEL_INTERFACE=$(sdwan_get_channel_configured_interface "$SDWAN_TUN_CHANNEL")
      if [[ -z "$SDWAN_TUN_CHANNEL_INTERFACE" ]]; then
        continue
      fi

      if [[ "$IP_FAMILY" == "-6" ]]; then
        nft add rule $FAMILY $TABLE POSTROUTING ip6 saddr @DEFAULT_ROUTE_IPV6 return
        SDWAN_TUN_CHANNEL_NAT_IGNORE_LOCAL=(ip6 daddr != @LOCAL_IPV6)
      else
        nft add rule $FAMILY $TABLE POSTROUTING ip saddr @DEFAULT_ROUTE_IPV4 return
        SDWAN_TUN_CHANNEL_NAT_IGNORE_LOCAL=(ip daddr != @LOCAL_IPV4)
      fi
      nft add rule $FAMILY $TABLE POSTROUTING meta mark and 0xf0 == $(printf "0x%x" $SDWAN_TUN_CHANNEL_MARK) oifname "$SDWAN_TUN_CHANNEL_INTERFACE" "${SDWAN_TUN_CHANNEL_NAT_IGNORE_LOCAL[@]}" meta l4proto udp counter packets 0 bytes 0 masquerade to :16000-65535
      nft add rule $FAMILY $TABLE POSTROUTING meta mark and 0xf0 == $(printf "0x%x" $SDWAN_TUN_CHANNEL_MARK) oifname "$SDWAN_TUN_CHANNEL_INTERFACE" "${SDWAN_TUN_CHANNEL_NAT_IGNORE_LOCAL[@]}" meta l4proto tcp counter packets 0 bytes 0 masquerade to :16000-65535
      nft add rule $FAMILY $TABLE POSTROUTING meta mark and 0xf0 == $(printf "0x%x" $SDWAN_TUN_CHANNEL_MARK) oifname "$SDWAN_TUN_CHANNEL_INTERFACE" "${SDWAN_TUN_CHANNEL_NAT_IGNORE_LOCAL[@]}" counter packets 0 bytes 0 masquerade
    done
  done
}

function sdwan_clear_ip_rules() {
  for IP_FAMILY in "$@"; do
    SDWAN_IP_RULE_EXCLUDE_IF_PRIORITY=$(($SDWAN_SKIP_IP_RULE_PRIORITY - 3))
    SDWAN_IP_RULE_EXCLUDE_MARK_PRIORITY=$(($SDWAN_SKIP_IP_RULE_PRIORITY - 2))
    SDWAN_IP_RULE_INCLUDE_MARK_PRIORITY=$(($SDWAN_SKIP_IP_RULE_PRIORITY - 1))
    SDWAN_IP_RULE_NO_MARK_DEFAULT_ROUTE_PRIORITY=$SDWAN_SKIP_IP_RULE_PRIORITY

    for CLEAR_PRIORITY in "$ROUTER_IP_RULE_GOTO_DEFAULT_PRIORITY" \
                          "$SDWAN_IP_RULE_EXCLUDE_IF_PRIORITY" \
                          "$SDWAN_IP_RULE_EXCLUDE_MARK_PRIORITY" \
                          "$SDWAN_IP_RULE_INCLUDE_MARK_PRIORITY" \
                          "$SDWAN_IP_RULE_NO_MARK_DEFAULT_ROUTE_PRIORITY"; do
      ROUTER_IP_RULE_LOOPUP_PRIORITY=$(ip $IP_FAMILY rule show priority $CLEAR_PRIORITY | awk 'END {print NF}')
      while [[ 0 -ne $ROUTER_IP_RULE_LOOPUP_PRIORITY ]]; do
        ip $IP_FAMILY rule delete priority $CLEAR_PRIORITY
        ROUTER_IP_RULE_LOOPUP_PRIORITY=$(ip $IP_FAMILY rule show priority $CLEAR_PRIORITY | awk 'END {print NF}')
      done
    done

    # clear ip route table
    for SDWAN_TUN_CHANNEL in "${SDWAN_TUN_CHANNELS[@]}"; do
      SDWAN_TUN_PROXY_CHANNEL_TABLE_ID=$(sdwan_get_channel_table_id "$SDWAN_TUN_CHANNEL")
      TABLE_RULE_COUNT=$(ip $IP_FAMILY route show table $SDWAN_TUN_PROXY_CHANNEL_TABLE_ID 2>/dev/null | wc -l)
      if [[ $TABLE_RULE_COUNT -gt 0 ]]; then
        ip $IP_FAMILY route flush table $SDWAN_TUN_PROXY_CHANNEL_TABLE_ID >/dev/null 2>&1 || true
      fi
    done
  done
}

function sdwan_setup_ip_rules() {
  FAMILY="$1"
  TABLE="$2"
  shift 2

  SDWAN_IP_RULE_EXCLUDE_IF_PRIORITY=$(($SDWAN_SKIP_IP_RULE_PRIORITY - 3))
  SDWAN_IP_RULE_EXCLUDE_MARK_PRIORITY=$(($SDWAN_SKIP_IP_RULE_PRIORITY - 2))
  SDWAN_IP_RULE_INCLUDE_MARK_PRIORITY=$(($SDWAN_SKIP_IP_RULE_PRIORITY - 1))
  SDWAN_IP_RULE_NO_MARK_DEFAULT_ROUTE_PRIORITY=$SDWAN_SKIP_IP_RULE_PRIORITY

  for IP_FAMILY in "$@"; do
    NOP_LOOKUP_PRIORITY=$ROUTER_IP_RULE_GOTO_DEFAULT_PRIORITY

    # If no proxy addresses, skip all rules setup
    if [[ "$IP_FAMILY" == "-6" ]]; then
      if [[ ${#IPV6_TUN_ADDRESS_SET[@]} -eq 0 ]]; then
        ip $IP_FAMILY rule add goto $NOP_LOOKUP_PRIORITY priority $SDWAN_IP_RULE_EXCLUDE_IF_PRIORITY >/dev/null 2>&1 || true
        continue
      fi
    else
      if [[ ${#IPV4_TUN_ADDRESS_SET[@]} -eq 0 ]]; then
        ip $IP_FAMILY rule add goto $NOP_LOOKUP_PRIORITY priority $SDWAN_IP_RULE_EXCLUDE_IF_PRIORITY >/dev/null 2>&1 || true
        continue
      fi
    fi

    ip $IP_FAMILY rule add nop priority $ROUTER_IP_RULE_GOTO_DEFAULT_PRIORITY >/dev/null 2>&1 || true
    ip $IP_FAMILY rule add fwmark 0xe0/0xf0 goto $NOP_LOOKUP_PRIORITY priority $SDWAN_IP_RULE_EXCLUDE_MARK_PRIORITY >/dev/null 2>&1 || true

    SDWAN_TUN_PROXY_CHANNEL_MARK=0
    SDWAN_ACTIVE_CHANNEL_COUNT=0
    for SDWAN_TUN_CHANNEL in "${SDWAN_TUN_CHANNELS[@]}"; do
      SDWAN_TUN_PROXY_CHANNEL_TABLE_ID=$(sdwan_get_channel_table_id "$SDWAN_TUN_CHANNEL")
      SDWAN_TUN_PROXY_CHANNEL_MARK=$(($SDWAN_TUN_PROXY_CHANNEL_MARK + 0x10))
      SDWAN_TUN_PROXY_CHANNEL_INTERFACE=$(sdwan_get_channel_configured_interface "$SDWAN_TUN_CHANNEL")
      SDWAN_TUN_PROXY_CHANNEL_ROUTE=(dev "$SDWAN_TUN_PROXY_CHANNEL_INTERFACE")
      if [[ -z "$SDWAN_TUN_PROXY_CHANNEL_INTERFACE" ]]; then
        echo "Warning: skip SD-WAN channel $SDWAN_TUN_CHANNEL because no live interface is available." >&2
        continue
      fi

      SDWAN_TUN_IP_ADDR=$(sdwan_wait_for_interface_address "$IP_FAMILY" "$SDWAN_TUN_PROXY_CHANNEL_INTERFACE" "$SDWAN_WAIT_READY_RETRY")
      if [[ -z "$SDWAN_TUN_IP_ADDR" ]]; then
        if [[ "$IP_FAMILY" == "-6" ]]; then
          echo "Warning: skip IPv6 SD-WAN channel $SDWAN_TUN_CHANNEL because interface $SDWAN_TUN_PROXY_CHANNEL_INTERFACE has no global IPv6 address yet." >&2
          continue
        fi

        echo "Error: IPv4 SD-WAN channel $SDWAN_TUN_CHANNEL interface $SDWAN_TUN_PROXY_CHANNEL_INTERFACE has no global IPv4 address yet." >&2
        return 1
      fi

      # Add ip to DEFAULT_ROUTE_IPV4/DEFAULT_ROUTE_IPV6
      if [[ "$IP_FAMILY" == "-6" ]]; then
        nft add element $FAMILY $TABLE DEFAULT_ROUTE_IPV6 { "$SDWAN_TUN_IP_ADDR" } >/dev/null 2>&1 || true
      else
        nft add element $FAMILY $TABLE DEFAULT_ROUTE_IPV4 { "$SDWAN_TUN_IP_ADDR" } >/dev/null 2>&1 || true
      fi

      sdwan_flush_route_table_if_exists "$IP_FAMILY" "$SDWAN_TUN_PROXY_CHANNEL_TABLE_ID"

      if [[ "$IP_FAMILY" == "-6" ]]; then
        for ROUTE_CIDR in "${IPV6_TUN_ADDRESS_SET[@]}"; do
          ip $IP_FAMILY route replace "$ROUTE_CIDR" dev "$SDWAN_TUN_PROXY_CHANNEL_INTERFACE" src "$SDWAN_TUN_IP_ADDR" table $SDWAN_TUN_PROXY_CHANNEL_TABLE_ID
        done
        for ROUTE_CIDR in "${IPV6_TUN_ADDRESS_THROW[@]}"; do
          ip $IP_FAMILY route replace throw "$ROUTE_CIDR" table $SDWAN_TUN_PROXY_CHANNEL_TABLE_ID
        done
      else
        for ROUTE_CIDR in "${IPV4_TUN_ADDRESS_SET[@]}"; do
          ip $IP_FAMILY route replace "$ROUTE_CIDR" "${SDWAN_TUN_PROXY_CHANNEL_ROUTE[@]}" src "$SDWAN_TUN_IP_ADDR" table $SDWAN_TUN_PROXY_CHANNEL_TABLE_ID
        done
        for ROUTE_CIDR in "${IPV4_TUN_ADDRESS_THROW[@]}"; do
          ip $IP_FAMILY route replace throw "$ROUTE_CIDR" table $SDWAN_TUN_PROXY_CHANNEL_TABLE_ID
        done
      fi

      ip $IP_FAMILY rule add fwmark $SDWAN_TUN_PROXY_CHANNEL_MARK/0xf0 lookup $SDWAN_TUN_PROXY_CHANNEL_TABLE_ID priority $SDWAN_IP_RULE_INCLUDE_MARK_PRIORITY >/dev/null 2>&1 || true
      SDWAN_ACTIVE_CHANNEL_COUNT=$(($SDWAN_ACTIVE_CHANNEL_COUNT + 1))
    done

    if [[ $SDWAN_ACTIVE_CHANNEL_COUNT -eq 0 ]]; then
      if [[ "$IP_FAMILY" == "-6" ]]; then
        echo "Warning: skip IPv6 SD-WAN policy rules because no active channel is ready." >&2
        continue
      fi

      echo "Error: no active IPv4 SD-WAN channel is ready." >&2
      return 1
    fi

    # NO mark to default route, 自动生成的ppp0没有指定src，触发重路由会导致ip不正确。所以默认路由还是指向原本的默认路由
    ip $IP_FAMILY rule add fwmark 0x0/0xf0 goto $NOP_LOOKUP_PRIORITY priority $SDWAN_IP_RULE_NO_MARK_DEFAULT_ROUTE_PRIORITY >/dev/null 2>&1 || true
  done
}

function sdwan_setup_rule_marks() {
  FAMILY="$1"
  TABLE="$2"

  # 如果以后要支持TPROXY，可以改POLICY_PACKET_GOTO_PROXY链即可
  nft flush chain $FAMILY $TABLE POLICY_PACKET_GOTO_DEFAULT >/dev/null 2>&1
  nft flush chain $FAMILY $TABLE POLICY_MARK_GOTO_DEFAULT >/dev/null 2>&1
  nft flush chain $FAMILY $TABLE POLICY_PACKET_GOTO_PROXY >/dev/null 2>&1
  for SDWAN_TUN_CHANNEL in "${SDWAN_TUN_CHANNELS[@]}"; do
    nft flush chain $FAMILY $TABLE POLICY_MARK_GOTO_PROXY_$SDWAN_TUN_CHANNEL >/dev/null 2>&1
  done

  TABLE_CONTENT=$(cat <<EOF
table $FAMILY $TABLE {
  chain POLICY_PACKET_GOTO_DEFAULT {
    accept
  }

  chain POLICY_MARK_GOTO_DEFAULT {
    meta mark set meta mark and 0xffffff0f xor 0xe0
    ct mark set meta mark
    goto POLICY_PACKET_GOTO_DEFAULT
  }

  chain POLICY_PACKET_GOTO_PROXY {
    accept
  }
EOF
)

  SDWAN_TUN_CHANNEL_MARK=0
  for SDWAN_TUN_CHANNEL in "${SDWAN_TUN_CHANNELS[@]}"; do
    SDWAN_TUN_CHANNEL_MARK=$(($SDWAN_TUN_CHANNEL_MARK + 0x10))
    TABLE_CONTENT="$TABLE_CONTENT

  chain POLICY_MARK_GOTO_PROXY_$SDWAN_TUN_CHANNEL {
    meta mark set meta mark and 0xffffff0f xor $(printf "0x%x" $SDWAN_TUN_CHANNEL_MARK)
    ct mark set meta mark
    goto POLICY_PACKET_GOTO_PROXY
  }"
  done
  TABLE_CONTENT="$TABLE_CONTENT
}
"

  printf '%s\n' "$TABLE_CONTENT" | nft -f -
}

function sdwan_initialize_rule_table_inet() {
  FAMILY="$1"
  TABLE="$2"

  # Check if sets already exist
  LOCAL_SERVICE_PORT_UDP_EXISTS=0
  LOCAL_SERVICE_PORT_TCP_EXISTS=0
  nft list set $FAMILY $TABLE LOCAL_SERVICE_PORT_UDP >/dev/null 2>&1 && LOCAL_SERVICE_PORT_UDP_EXISTS=1
  nft list set $FAMILY $TABLE LOCAL_SERVICE_PORT_TCP >/dev/null 2>&1 && LOCAL_SERVICE_PORT_TCP_EXISTS=1

  if [[ $LOCAL_SERVICE_PORT_UDP_EXISTS -eq 0 ]] || [[ $LOCAL_SERVICE_PORT_TCP_EXISTS -eq 0 ]]; then
    LOCAL_SERVICE_PORT_UDP_ELEMENTS="$ROUTER_INTERNAL_SERVICE_PORT_UDP"
    if [[ -n "$ROUTER_INTERNAL_DIRECTLY_VISIT_UDP_DPORT" ]]; then
      LOCAL_SERVICE_PORT_UDP_ELEMENTS="$LOCAL_SERVICE_PORT_UDP_ELEMENTS, $ROUTER_INTERNAL_DIRECTLY_VISIT_UDP_DPORT"
    fi

    nft -f - <<EOF
table $FAMILY $TABLE {
$(if [[ $LOCAL_SERVICE_PORT_UDP_EXISTS -eq 0 ]]; then
cat <<INNER_EOF
  set LOCAL_SERVICE_PORT_UDP {
    type inet_service
    flags interval
    auto-merge
    elements = { $LOCAL_SERVICE_PORT_UDP_ELEMENTS }
  }
INNER_EOF
fi)
$(if [[ $LOCAL_SERVICE_PORT_TCP_EXISTS -eq 0 ]]; then
cat <<INNER_EOF
  set LOCAL_SERVICE_PORT_TCP {
    type inet_service
    flags interval
    auto-merge
    elements = { $ROUTER_INTERNAL_SERVICE_PORT_TCP }
  }
INNER_EOF
fi)
}
EOF
  fi
}

function sdwan_initialize_rule_table_ipv4() {
  FAMILY="$1"
  TABLE="$2"

  # Check if sets already exist
  BLACKLIST_IPV4_EXISTS=0
  GEOIP_CN_IPV4_EXISTS=0
  LOCAL_IPV4_EXISTS=0
  DEFAULT_ROUTE_IPV4_EXISTS=0
  SDWAN_TUN_PROXY_CHANNEL_NFT_SET=""
  SDWAN_TUN_PROXY_CHANNEL_NFT_JUMP=""
  for SDWAN_TUN_CHANNEL in "${SDWAN_TUN_CHANNELS[@]}"; do
    SDWAN_TUN_PROXY_CHANNEL_TABLE_ID_VAR="SDWAN_TUN_PROXY_WHITELIST_TABLE_ID_${SDWAN_TUN_CHANNEL}"
    SDWAN_TUN_PROXY_CHANNEL_TABLE_ID="${!SDWAN_TUN_PROXY_CHANNEL_TABLE_ID_VAR}"
    SDWAN_TUN_PROXY_CHANNEL_IPV4_EXISTS=0
    nft list set $FAMILY $TABLE PROXY_${SDWAN_TUN_CHANNEL}_IPV4 >/dev/null 2>&1 && SDWAN_TUN_PROXY_CHANNEL_IPV4_EXISTS=1
    if [[ $SDWAN_TUN_PROXY_CHANNEL_IPV4_EXISTS -eq 0 ]]; then
      if [[ "$SDWAN_TUN_CHANNEL" == "${SDWAN_TUN_CHANNELS[0]}" ]]; then
        SDWAN_TUN_PROXY_CHANNEL_NFT_SET="$SDWAN_TUN_PROXY_CHANNEL_NFT_SET
  set PROXY_${SDWAN_TUN_CHANNEL}_IPV4 {
    type ipv4_addr
    flags interval
    auto-merge
    elements = { 8.8.8.8/32, 8.8.4.4/32, 1.1.1.1/32, 1.0.0.1/32 }
  }"
      else
        SDWAN_TUN_PROXY_CHANNEL_NFT_SET="$SDWAN_TUN_PROXY_CHANNEL_NFT_SET
  set PROXY_${SDWAN_TUN_CHANNEL}_IPV4 {
    type ipv4_addr
    flags interval
    auto-merge
  }"
      fi
    fi
    SDWAN_TUN_PROXY_CHANNEL_NFT_JUMP="$SDWAN_TUN_PROXY_CHANNEL_NFT_JUMP
    ip daddr @PROXY_${SDWAN_TUN_CHANNEL}_IPV4 jump POLICY_MARK_GOTO_PROXY_$SDWAN_TUN_CHANNEL"
  done
  nft list set $FAMILY $TABLE BLACKLIST_IPV4 >/dev/null 2>&1 && BLACKLIST_IPV4_EXISTS=1
  nft list set $FAMILY $TABLE GEOIP_CN_IPV4 >/dev/null 2>&1 && GEOIP_CN_IPV4_EXISTS=1
  nft list set $FAMILY $TABLE LOCAL_IPV4 >/dev/null 2>&1 && LOCAL_IPV4_EXISTS=1
  nft list set $FAMILY $TABLE DEFAULT_ROUTE_IPV4 >/dev/null 2>&1 && DEFAULT_ROUTE_IPV4_EXISTS=1

  nft flush chain $FAMILY $TABLE POLICY_SDWAN_IPV4 >/dev/null 2>&1

  nft -f - <<EOF
table $FAMILY $TABLE {
$(if [[ $BLACKLIST_IPV4_EXISTS -eq 0 ]]; then
cat <<INNER_EOF
  set BLACKLIST_IPV4 {
    type ipv4_addr
    flags interval
    auto-merge
  }
INNER_EOF
fi)
$(if [[ $GEOIP_CN_IPV4_EXISTS -eq 0 ]]; then
cat <<INNER_EOF
  set GEOIP_CN_IPV4 {
    type ipv4_addr
    flags interval
    auto-merge
  }
INNER_EOF
fi)
$(if [[ $LOCAL_IPV4_EXISTS -eq 0 ]]; then
cat <<INNER_EOF
  set LOCAL_IPV4 {
    type ipv4_addr
    flags interval
    auto-merge
    elements = { 0.0.0.0/8, 10.0.0.0/8, 127.0.0.0/8, 169.254.0.0/16, 172.16.0.0/12, 192.0.0.0/24, 192.168.0.0/16, 224.0.0.0/4, 240.0.0.0/4 }
  }
INNER_EOF
fi)
$(if [[ $DEFAULT_ROUTE_IPV4_EXISTS -eq 0 ]]; then
cat <<INNER_EOF
  set DEFAULT_ROUTE_IPV4 {
    type ipv4_addr
    flags interval
    auto-merge
  }
INNER_EOF
fi)
$SDWAN_TUN_PROXY_CHANNEL_NFT_SET

  chain POLICY_SDWAN_IPV4 {
    # ipv4 - local network
    ip saddr @LOCAL_IPV4 ip daddr @LOCAL_IPV4 jump POLICY_MARK_GOTO_DEFAULT

    # blacklist
    ip daddr @BLACKLIST_IPV4 jump POLICY_MARK_GOTO_DEFAULT

    # ipv4 - DNAT or connect from outside
    ip saddr @LOCAL_IPV4 tcp sport @LOCAL_SERVICE_PORT_TCP jump POLICY_MARK_GOTO_DEFAULT
    ip saddr @LOCAL_IPV4 udp sport @LOCAL_SERVICE_PORT_UDP jump POLICY_MARK_GOTO_DEFAULT
    ip saddr @DEFAULT_ROUTE_IPV4 tcp sport @LOCAL_SERVICE_PORT_TCP jump POLICY_MARK_GOTO_DEFAULT
    ip saddr @DEFAULT_ROUTE_IPV4 udp sport @LOCAL_SERVICE_PORT_UDP jump POLICY_MARK_GOTO_DEFAULT

    ### ipv4 - skip link-local and broadcast address, 172.20.1.1/24 is used for remote debug
    ip daddr { 224.0.0.0/4, 255.255.255.255/32, 172.20.1.1/24 } jump POLICY_MARK_GOTO_DEFAULT

    ### ipv4 - skip private network and UDP of DNS
    ip daddr @LOCAL_IPV4 tcp dport @LOCAL_SERVICE_PORT_TCP jump POLICY_MARK_GOTO_DEFAULT
    ip daddr @LOCAL_IPV4 udp dport @LOCAL_SERVICE_PORT_UDP jump POLICY_MARK_GOTO_DEFAULT
    ip daddr @DEFAULT_ROUTE_IPV4 tcp dport @LOCAL_SERVICE_PORT_TCP jump POLICY_MARK_GOTO_DEFAULT
    ip daddr @DEFAULT_ROUTE_IPV4 udp dport @LOCAL_SERVICE_PORT_UDP jump POLICY_MARK_GOTO_DEFAULT

    # ipv4 skip package from outside
    ip daddr @GEOIP_CN_IPV4 jump POLICY_MARK_GOTO_DEFAULT

    ### ipv4 - default goto sdwan
    ${SDWAN_TUN_PROXY_CHANNEL_NFT_JUMP}
    jump POLICY_MARK_GOTO_DEFAULT
  }
}
EOF

  # Add blacklist elements if any
  if [[ ${#SDWAN_TUN_PROXY_BLACKLIST_IPV4[@]} -gt 0 ]]; then
    nft add element $FAMILY $TABLE BLACKLIST_IPV4 "{ $(echo "${SDWAN_TUN_PROXY_BLACKLIST_IPV4[@]}" | tr ' ' ',') }"
  fi
}

function sdwan_initialize_rule_table_ipv6() {
  FAMILY="$1"
  TABLE="$2"

  # Check if sets already exist
  BLACKLIST_IPV6_EXISTS=0
  GEOIP_CN_IPV6_EXISTS=0
  LOCAL_IPV6_EXISTS=0
  DEFAULT_ROUTE_IPV6_EXISTS=0
  SDWAN_TUN_PROXY_CHANNEL_NFT_SET=""
  SDWAN_TUN_PROXY_CHANNEL_NFT_JUMP=""
  for SDWAN_TUN_CHANNEL in "${SDWAN_TUN_CHANNELS[@]}"; do
    SDWAN_TUN_PROXY_CHANNEL_IPV6_EXISTS=0
    nft list set $FAMILY $TABLE PROXY_${SDWAN_TUN_CHANNEL}_IPV6 >/dev/null 2>&1 && SDWAN_TUN_PROXY_CHANNEL_IPV6_EXISTS=1
    if [[ $SDWAN_TUN_PROXY_CHANNEL_IPV6_EXISTS -eq 0 ]]; then
      if [[ "$SDWAN_TUN_CHANNEL" == "${SDWAN_TUN_CHANNELS[0]}" ]]; then
        SDWAN_TUN_PROXY_CHANNEL_NFT_SET="$SDWAN_TUN_PROXY_CHANNEL_NFT_SET
  set PROXY_${SDWAN_TUN_CHANNEL}_IPV6 {
    type ipv6_addr
    flags interval
    auto-merge
    elements = { 2001:4860:4860::8888/128, 2001:4860:4860::8844/128, 2606:4700:4700::1111/128, 2606:4700:4700::1001/128 }
  }"
      else
        SDWAN_TUN_PROXY_CHANNEL_NFT_SET="$SDWAN_TUN_PROXY_CHANNEL_NFT_SET
  set PROXY_${SDWAN_TUN_CHANNEL}_IPV6 {
    type ipv6_addr
    flags interval
    auto-merge
  }"
      fi
    fi
    SDWAN_TUN_PROXY_CHANNEL_NFT_JUMP="$SDWAN_TUN_PROXY_CHANNEL_NFT_JUMP
    ip6 daddr @PROXY_${SDWAN_TUN_CHANNEL}_IPV6 jump POLICY_MARK_GOTO_PROXY_$SDWAN_TUN_CHANNEL"
  done
  nft list set $FAMILY $TABLE BLACKLIST_IPV6 >/dev/null 2>&1 && BLACKLIST_IPV6_EXISTS=1
  nft list set $FAMILY $TABLE GEOIP_CN_IPV6 >/dev/null 2>&1 && GEOIP_CN_IPV6_EXISTS=1
  nft list set $FAMILY $TABLE LOCAL_IPV6 >/dev/null 2>&1 && LOCAL_IPV6_EXISTS=1
  nft list set $FAMILY $TABLE DEFAULT_ROUTE_IPV6 >/dev/null 2>&1 && DEFAULT_ROUTE_IPV6_EXISTS=1

  nft flush chain $FAMILY $TABLE POLICY_SDWAN_IPV6 >/dev/null 2>&1

  nft -f - <<EOF
table $FAMILY $TABLE {
$(if [[ $BLACKLIST_IPV6_EXISTS -eq 0 ]]; then
cat <<INNER_EOF
  set BLACKLIST_IPV6 {
    type ipv6_addr
    flags interval
    auto-merge
  }
INNER_EOF
fi)
$(if [[ $GEOIP_CN_IPV6_EXISTS -eq 0 ]]; then
cat <<INNER_EOF
  set GEOIP_CN_IPV6 {
    type ipv6_addr
    flags interval
    auto-merge
  }
INNER_EOF
fi)
$(if [[ $LOCAL_IPV6_EXISTS -eq 0 ]]; then
cat <<INNER_EOF
  set LOCAL_IPV6 {
    type ipv6_addr
    flags interval
    auto-merge
    elements = { ::1/128, ::/128, ::ffff:0:0/96, 64:ff9b::/96, 100::/64, fc00::/7, fe80::/10, ff00::/8 }
  }
INNER_EOF
fi)
$(if [[ $DEFAULT_ROUTE_IPV6_EXISTS -eq 0 ]]; then
cat <<INNER_EOF
  set DEFAULT_ROUTE_IPV6 {
    type ipv6_addr
    flags interval
    auto-merge
  }
INNER_EOF
fi)
$SDWAN_TUN_PROXY_CHANNEL_NFT_SET

  chain POLICY_SDWAN_IPV6 {
    # ipv6 - local network
    ip6 saddr @LOCAL_IPV6 ip6 daddr @LOCAL_IPV6 jump POLICY_MARK_GOTO_DEFAULT

    # blacklist
    ip6 daddr @BLACKLIST_IPV6 jump POLICY_MARK_GOTO_DEFAULT

    # ipv6 - DNAT or connect from outside
    ip6 saddr @LOCAL_IPV6 tcp sport @LOCAL_SERVICE_PORT_TCP jump POLICY_MARK_GOTO_DEFAULT
    ip6 saddr @LOCAL_IPV6 udp sport @LOCAL_SERVICE_PORT_UDP jump POLICY_MARK_GOTO_DEFAULT
    ip6 saddr @DEFAULT_ROUTE_IPV6 tcp sport @LOCAL_SERVICE_PORT_TCP jump POLICY_MARK_GOTO_DEFAULT
    ip6 saddr @DEFAULT_ROUTE_IPV6 udp sport @LOCAL_SERVICE_PORT_UDP jump POLICY_MARK_GOTO_DEFAULT

    ### ipv6 - skip private network and UDP of DNS
    ip6 daddr @LOCAL_IPV6 tcp dport @LOCAL_SERVICE_PORT_TCP jump POLICY_MARK_GOTO_DEFAULT
    ip6 daddr @LOCAL_IPV6 udp dport @LOCAL_SERVICE_PORT_UDP jump POLICY_MARK_GOTO_DEFAULT
    ip6 daddr @DEFAULT_ROUTE_IPV6 tcp dport @LOCAL_SERVICE_PORT_TCP jump POLICY_MARK_GOTO_DEFAULT
    ip6 daddr @DEFAULT_ROUTE_IPV6 udp dport @LOCAL_SERVICE_PORT_UDP jump POLICY_MARK_GOTO_DEFAULT

    # ipv6 skip package from outside
    ip6 daddr @GEOIP_CN_IPV6 jump POLICY_MARK_GOTO_DEFAULT

    ### ipv6 - default goto sdwan
    ${SDWAN_TUN_PROXY_CHANNEL_NFT_JUMP}
    jump POLICY_MARK_GOTO_DEFAULT
  }
}
EOF

  # Add blacklist elements if any
  if [[ ${#SDWAN_TUN_PROXY_BLACKLIST_IPV6[@]} -gt 0 ]]; then
    nft add element $FAMILY $TABLE BLACKLIST_IPV6 "{ $(echo "${SDWAN_TUN_PROXY_BLACKLIST_IPV6[@]}" | tr ' ' ',') }"
  fi
  if [[ ${#IPV6_TUN_ADDRESS_THROW[@]} -gt 0 ]]; then
    nft add element $FAMILY $TABLE BLACKLIST_IPV6 "{ $(echo "${IPV6_TUN_ADDRESS_THROW[@]}" | tr ' ' ',') }"
  fi
}

function sdwan_initialize_rule_table() {
  FAMILY="$1"
  TABLE="$2"

  if ! nft list table $FAMILY $TABLE >/dev/null 2>&1; then
    nft add table $FAMILY $TABLE
  fi

  sdwan_setup_rule_marks "$FAMILY" "$TABLE"
  sdwan_initialize_rule_table_inet "$FAMILY" "$TABLE"
  sdwan_initialize_rule_table_ipv4 "$FAMILY" "$TABLE"
  sdwan_initialize_rule_table_ipv6 "$FAMILY" "$TABLE"

  nft flush chain $FAMILY $TABLE POLICY_SDWAN_BOOTSTRAP >/dev/null 2>&1

  nft -f - <<EOF
table $FAMILY $TABLE {
  chain POLICY_SDWAN_BOOTSTRAP {
    meta mark and 0xf0 != 0x0 ct mark and 0xf0 == 0x0 ct mark set meta mark accept
    meta mark and 0xf0 != 0x0 accept
    ct mark and 0xf0 != 0x0 meta mark set ct mark accept

    ip version 4 jump POLICY_SDWAN_IPV4
    ip6 version 6 jump POLICY_SDWAN_IPV6
  }
}
EOF
}

function sdwan_setup_rule_chain() {
  FAMILY="$1"
  TABLE="$2"
  CHAIN="$3"

  shift
  shift
  shift

  if ! nft list chain $FAMILY $TABLE $CHAIN >/dev/null 2>&1; then
    nft add chain $FAMILY $TABLE $CHAIN "$@"
  fi
  nft flush chain $FAMILY $TABLE $CHAIN

  nft add rule $FAMILY $TABLE $CHAIN jump POLICY_SDWAN_BOOTSTRAP
}

function sdwan_remove_rule_marks() {
  FAMILY="$1"
  TABLE="$2"

  nft delete chain $FAMILY $TABLE POLICY_SDWAN_BOOTSTRAP >/dev/null 2>&1
  nft delete chain $FAMILY $TABLE POLICY_SDWAN_IPV4 >/dev/null 2>&1
  nft delete chain $FAMILY $TABLE POLICY_SDWAN_IPV6 >/dev/null 2>&1
  nft delete chain $FAMILY $TABLE POLICY_MARK_GOTO_DEFAULT >/dev/null 2>&1
  nft delete chain $FAMILY $TABLE POLICY_PACKET_GOTO_DEFAULT >/dev/null 2>&1
  nft delete chain $FAMILY $TABLE POLICY_PACKET_GOTO_PROXY >/dev/null 2>&1
  for SDWAN_TUN_CHANNEL in "${SDWAN_TUN_CHANNELS[@]}"; do
    SDWAN_TUN_PROXY_CHANNEL_TABLE_ID_VAR="SDWAN_TUN_PROXY_WHITELIST_TABLE_ID_${SDWAN_TUN_CHANNEL}"
    SDWAN_TUN_PROXY_CHANNEL_TABLE_ID="${!SDWAN_TUN_PROXY_CHANNEL_TABLE_ID_VAR}"
    nft delete chain $FAMILY $TABLE POLICY_MARK_GOTO_PROXY_$SDWAN_TUN_CHANNEL >/dev/null 2>&1
  done
}

function sdwan_update_geoip() {
  # Update GEOIP
  if [[ ! -e "$SDWAN_DATA_DIR/geoip-cn.json" ]]; then
    echo "$SDWAN_DATA_DIR/geoip-cn.json not found"
    exit 1
  fi

  # 使用 jq 直接生成逗号分隔的 IP 列表，避免 bash 数组的性能问题
  GEOIP_CN_IPV4_LIST=$(jq -r '.rules[].ip_cidr[]' "$SDWAN_DATA_DIR/geoip-cn.json" | grep -v ':' | tr '\n' ',' | sed 's/,$//')
  GEOIP_CN_IPV6_LIST=$(jq -r '.rules[].ip_cidr[]' "$SDWAN_DATA_DIR/geoip-cn.json" | grep ':' | tr '\n' ',' | sed 's/,$//')

  # 一次性刷入所有 GEOIP 数据
  nft -f - <<EOF
table inet sdwan {
  set GEOIP_CN_IPV4 {
    type ipv4_addr
    flags interval
    auto-merge
    elements = { $GEOIP_CN_IPV4_LIST }
  }
  set GEOIP_CN_IPV6 {
    type ipv6_addr
    flags interval
    auto-merge
    elements = { $GEOIP_CN_IPV6_LIST }
  }
}
table bridge sdwan {
  set GEOIP_CN_IPV4 {
    type ipv4_addr
    flags interval
    auto-merge
    elements = { $GEOIP_CN_IPV4_LIST }
  }
  set GEOIP_CN_IPV6 {
    type ipv6_addr
    flags interval
    auto-merge
    elements = { $GEOIP_CN_IPV6_LIST }
  }
}
EOF
}

if [[ $SDWAN_SETUP_IP_RULE_CLEAR -eq 0 ]]; then
  sdwan_clear_ip_rules "-4" "-6"
  sdwan_initialize_rule_table inet sdwan
  sdwan_initialize_rule_table bridge sdwan

  sdwan_setup_rule_chain inet sdwan PREROUTING '{ type filter hook prerouting priority dstnat - 1 ; }'
  # 必须在高优先级（mangle）打标记，否则无法影响重路由
  sdwan_setup_rule_chain inet sdwan OUTPUT '{ type route hook output priority mangle - 1 ; }'

  sdwan_setup_rule_chain bridge sdwan PREROUTING '{ type filter hook prerouting priority -280; }'

  # setup ip rules ourself
  sdwan_setup_ip_rules inet sdwan "-4" "-6" || exit 1
  sdwan_setup_snat_table inet sdwan "-4" "-6"

  sdwan_update_geoip

  # clear DNS server cache
  # su tools -l -c 'env XDG_RUNTIME_DIR="/run/user/$UID" DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR}/bus" systemctl --user restart container-adguard-home'

else
  sdwan_clear_ip_rules "-4" "-6"
  sdwan_remove_snat_table inet sdwan "-4" "-6"

  nft delete chain inet sdwan PREROUTING >/dev/null 2>&1
  nft delete chain inet sdwan OUTPUT >/dev/null 2>&1

  nft delete chain bridge sdwan PREROUTING >/dev/null 2>&1

  sdwan_remove_rule_marks inet sdwan
  sdwan_remove_rule_marks bridge sdwan

  nft flush set inet sdwan GEOIP_CN_IPV4
  nft flush set inet sdwan GEOIP_CN_IPV6
  nft flush set bridge sdwan GEOIP_CN_IPV4
  nft flush set bridge sdwan GEOIP_CN_IPV6
fi

