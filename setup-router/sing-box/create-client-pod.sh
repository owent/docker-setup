#!/bin/bash

# $ROUTER_HOME/sing-box/create-client-pod.sh

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
source "$(dirname "$SCRIPT_DIR")/configure-router.sh"

### 策略路由(占用mark的后8位,RPDB变化均会触发重路由):
###   不需要重路由设置: 设置 fwmark = 0x0e/0x0f (00001110)
###   直接跳转到默认路由: 跳过 fwmark = 0x70/0x70 (01110000)
###   所有 fwmark = 0x0e/0x0f 的包正常走 tun
###     (vbox会设置511,0x1ff), 避开 0x0e/0x0f 规则(跳过table 100)，满足 0x70/0x70 规则(防止循环重定向)

if [[ -z "$ROUTER_IP_RULE_GOTO_DEFAULT_PRIORITY" ]]; then
  ROUTER_IP_RULE_GOTO_DEFAULT_PRIORITY=20901
fi
if [[ -z "$VBOX_SKIP_IP_RULE_PRIORITY" ]]; then
  VBOX_SKIP_IP_RULE_PRIORITY=8123
fi

if [[ -z "$VBOX_ETC_DIR" ]]; then
  VBOX_ETC_DIR="$HOME/vbox/etc"
fi
if [[ -z "$VBOX_DATA_DIR" ]]; then
  VBOX_DATA_DIR="$HOME/vbox/data"
fi
if [[ -z "$VBOX_LOG_DIR" ]]; then
  if [[ ! -z "$ROUTER_LOG_ROOT_DIR" ]]; then
    VBOX_LOG_DIR="$ROUTER_LOG_ROOT_DIR/vbox"
  else
    VBOX_LOG_DIR="$HOME/vbox/data"
  fi
fi

mkdir -p "$VBOX_ETC_DIR"
mkdir -p "$VBOX_DATA_DIR"
mkdir -p "$VBOX_LOG_DIR"

if [[ "x$VBOX_UPDATE" != "x" ]] || [[ "x$ROUTER_IMAGE_UPDATE" != "x" ]]; then
  podman pull docker.io/owt5008137/vbox:latest
  if [[ $? -ne 0 ]]; then
    exit 1
  fi
fi

systemctl disable vbox-client || true
systemctl stop vbox-client || true

podman container inspect vbox-client >/dev/null 2>&1
if [[ $? -eq 0 ]]; then
  podman stop vbox-client
  podman rm -f vbox-client
fi

if [[ "x$VBOX_UPDATE" != "x" ]] || [[ "x$ROUTER_IMAGE_UPDATE" != "x" ]]; then
  podman image prune -a -f --filter "until=240h"
fi

podman run -d --name vbox-client --cap-add=NET_ADMIN --cap-add=NET_BIND_SERVICE \
  --network=host --security-opt label=disable \
  --device /dev/net/tun:/dev/net/tun \
  --mount type=bind,source=$VBOX_ETC_DIR,target=/etc/vbox/,ro=true \
  --mount type=bind,source=$VBOX_DATA_DIR,target=/var/lib/vbox \
  --mount type=bind,source=$VBOX_LOG_DIR,target=/var/log/vbox \
  --mount type=bind,source=$ACMESH_SSL_DIR,target=/data/ssl,ro=true \
  docker.io/owt5008137/vbox:latest -D /var/lib/vbox -C /etc/vbox/ run

# podman cp vbox-client:/usr/local/vbox-client/share/geo-all.tar.gz geo-all.tar.gz
# if [[ $? -eq 0 ]]; then
#   tar -axvf geo-all.tar.gz
#   if [ $? -eq 0 ]; then
#     bash "$SCRIPT_DIR/setup-geoip-geosite.sh"
#   fi
# fi

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

if [ $ROUTER_NET_LOCAL_ENABLE_VBOX -ne 0 ]; then
  ip -4 rule add nop priority $ROUTER_IP_RULE_GOTO_DEFAULT_PRIORITY
  ip -6 rule add nop priority $ROUTER_IP_RULE_GOTO_DEFAULT_PRIORITY
  ip -4 rule add fwmark 0x70/0x70 goto $ROUTER_IP_RULE_GOTO_DEFAULT_PRIORITY priority $VBOX_SKIP_IP_RULE_PRIORITY
  ip -6 rule add fwmark 0x70/0x70 goto $ROUTER_IP_RULE_GOTO_DEFAULT_PRIORITY priority $VBOX_SKIP_IP_RULE_PRIORITY

  nft list table ip vbox >/dev/null 2>&1
  if [[ $? -ne 0 ]]; then
    nft add table ip vbox
  fi

  if [[ $TPROXY_SETUP_WITHOUT_IPV6 -eq 0 ]]; then
    nft list table ip6 vbox >/dev/null 2>&1
    if [ $? -ne 0 ]; then
      nft add table ip6 vbox
    fi
  fi

  nft list table bridge vbox >/dev/null 2>&1
  if [[ $? -ne 0 ]]; then
    nft add table bridge vbox
  fi

  ### Setup - ipv4
  nft list set ip vbox BLACKLIST >/dev/null 2>&1
  if [[ $? -ne 0 ]]; then
    nft add set ip vbox BLACKLIST '{ type ipv4_addr; }'
  fi
  nft list set ip vbox GEOIP_CN >/dev/null 2>&1
  if [[ $? -ne 0 ]]; then
    nft add set ip vbox GEOIP_CN '{ type ipv4_addr; }'
  fi
  nft list set ip vbox LOCAL_IPV4 >/dev/null 2>&1
  if [[ $? -ne 0 ]]; then
    nft add set ip vbox LOCAL_IPV4 '{ type ipv4_addr; flags interval; auto-merge ; }'
    nft add element ip vbox LOCAL_IPV4 '{127.0.0.1/32, 169.254.0.0/16, 192.168.0.0/16, 172.16.0.0/12, 10.0.0.0/8}'
  fi
  nft list set ip vbox DEFAULT_ROUTE_IPV4 >/dev/null 2>&1
  if [[ $? -ne 0 ]]; then
    nft add set ip vbox DEFAULT_ROUTE_IPV4 '{ type ipv4_addr; flags interval; auto-merge ; }'
  fi

  ### Setup - ipv6
  nft list set ip6 vbox BLACKLIST >/dev/null 2>&1
  if [[ $? -ne 0 ]]; then
    nft add set ip6 vbox BLACKLIST '{ type ipv6_addr; }'
  fi
  nft list set ip6 vbox GEOIP_CN >/dev/null 2>&1
  if [[ $? -ne 0 ]]; then
    nft add set ip6 vbox GEOIP_CN '{ type ipv6_addr; }'
  fi
  nft list set ip6 vbox LOCAL_IPV6 >/dev/null 2>&1
  if [[ $? -ne 0 ]]; then
    nft add set ip6 vbox LOCAL_IPV6 '{ type ipv6_addr; flags interval; auto-merge ; }'
    nft add element ip6 vbox LOCAL_IPV6 '{::1/128, fc00::/7, fe80::/10}'
  fi
  nft list set ip6 vbox DEFAULT_ROUTE_IPV6 >/dev/null 2>&1
  if [[ $? -ne 0 ]]; then
    nft add set ip6 vbox DEFAULT_ROUTE_IPV6 '{ type ipv6_addr; flags interval; auto-merge ; }'
  fi

  nft list chain ip vbox PREROUTING >/dev/null 2>&1
  if [[ $? -ne 0 ]]; then
    nft add chain ip vbox PREROUTING '{ type filter hook prerouting priority filter + 1 ; }'
  fi
  nft flush chain ip vbox PREROUTING

  ### Setup - ipv6
  nft list set bridge vbox BLACKLIST_IPV4 >/dev/null 2>&1
  if [[ $? -ne 0 ]]; then
    nft add set bridge vbox BLACKLIST_IPV4 '{ type ipv4_addr; flags interval; auto-merge; }'
  fi
  nft list set bridge vbox LOCAL_IPV4 >/dev/null 2>&1
  if [ $? -ne 0 ]; then
    nft add set bridge vbox LOCAL_IPV4 '{ type ipv4_addr; flags interval; auto-merge ; }'
    nft add element bridge vbox LOCAL_IPV4 '{127.0.0.1/32, 169.254.0.0/16, 192.168.0.0/16, 172.16.0.0/12, 10.0.0.0/8}'
  fi
  nft list set bridge vbox DEFAULT_ROUTE_IPV4 >/dev/null 2>&1
  if [ $? -ne 0 ]; then
    nft add set bridge vbox DEFAULT_ROUTE_IPV4 '{ type ipv4_addr; flags interval; auto-merge; }'
  fi

  nft list set bridge vbox BLACKLIST_IPV6 >/dev/null 2>&1
  if [[ $? -ne 0 ]]; then
    nft add set bridge vbox BLACKLIST_IPV6 '{ type ipv6_addr; flags interval; auto-merge; }'
  fi
  nft list set bridge vbox LOCAL_IPV6 >/dev/null 2>&1
  if [ $? -ne 0 ]; then
    nft add set bridge vbox LOCAL_IPV6 '{ type ipv6_addr; flags interval; auto-merge; }'
    nft add element bridge vbox LOCAL_IPV6 '{::1/128, fc00::/7, fe80::/10}'
  fi
  nft list set bridge vbox DEFAULT_ROUTE_IPV6 >/dev/null 2>&1
  if [ $? -ne 0 ]; then
    nft add set bridge vbox DEFAULT_ROUTE_IPV6 '{ type ipv6_addr; flags interval; auto-merge ; }'
  fi
else
  nft delete chain ip vbox PREROUTING >/dev/null 2>&1
  nft delete chain ip vbox OUTPUT >/dev/null 2>&1
  nft delete chain ip6 vbox PREROUTING >/dev/null 2>&1
  nft delete chain ip6 vbox OUTPUT >/dev/null 2>&1
  nft delete chain bridge vbox PREROUTING >/dev/null 2>&1
fi

# Start systemd service

podman generate systemd vbox-client | tee /lib/systemd/system/vbox-client.service

podman container stop vbox-client

systemctl daemon-reload

# patch end
systemctl enable vbox-client
systemctl start vbox-client
