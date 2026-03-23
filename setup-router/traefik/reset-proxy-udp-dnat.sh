#!/bin/bash

# ============================================================================
# 游戏 DS UDP 端口 DNAT 转发 (动态 PPP IP -> DS 后端)
# ============================================================================
# 当 PPP 接口 IP 变化时, 通过 nftables DNAT 将指定接口上的 UDP 端口
# 转发到后端 DS。与 Traefik 的静态 IP entryPoint 互补。
#
# 安装:
#   1. 在 configure-router.sh 中配置变量 (见下方)
#   2. 安装 NM dispatcher 钩子:
#      echo '#!/bin/bash
#      /bin/bash /PATH/TO/setup-router/traefik/reset-proxy-udp-dnat.sh
#      ' > /etc/NetworkManager/dispatcher.d/up.d/51-proxy-udp-dnat.sh
#      chmod +x /etc/NetworkManager/dispatcher.d/up.d/51-proxy-udp-dnat.sh
#
#   也可以在 reset-local-address-run.sh 中追加调用。
#
# 手动执行:
#   bash reset-proxy-udp-dnat.sh
#   bash reset-proxy-udp-dnat.sh -c    # 清理规则
# ============================================================================

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"

if [[ -e "$(dirname "$SCRIPT_DIR")/../configure-router.sh" ]]; then
  source "$(dirname "$SCRIPT_DIR")/../configure-router.sh"
fi

# ============================================================================
# 可配置变量 (可在 configure-router.sh 中覆盖)
# ============================================================================
# 监听接口列表 (默认 ppp0; 支持多个, 如 ppp0 ppp1)
if [[ -z "$TRAEFIK_DS_DNAT_IFACES" ]]; then
  TRAEFIK_DS_DNAT_IFACES=(ppp0 ens19.2)
fi

# 后端 DS 地址 (IPv4)
if [[ -z "$TRAEFIK_DS_DNAT_BACKEND" ]]; then
  TRAEFIK_DS_DNAT_BACKEND="10.64.8.101"
fi

# 后端 DS 地址 (IPv6, 可选; 留空则不配置 IPv6 DNAT)
TRAEFIK_DS_DNAT_BACKEND_V6="fd01:0:1:a40:0:40:800:65"

# UDP 端口范围
if [[ -z "$TRAEFIK_DS_DNAT_PORTS" ]]; then
  TRAEFIK_DS_DNAT_PORTS="7777-7782"
fi

# nftables 表名
DNAT_TABLE="traefik_project_x_ds_dnat"

# ============================================================================
# 参数解析
# ============================================================================
CLEANUP_ONLY=0
while getopts "ch" OPTION; do
  case $OPTION in
  c)
    CLEANUP_ONLY=1
    ;;
  h)
    echo "usage: $0 [options]"
    echo "options:"
    echo "  -c    仅清理 DNAT 规则"
    echo "  -h    显示帮助"
    exit 0
    ;;
  ?)
    break
    ;;
  esac
done

# ============================================================================
# 清理模式
# ============================================================================
if [[ $CLEANUP_ONLY -eq 1 ]]; then
  nft delete table ip "$DNAT_TABLE" 2>/dev/null
  nft delete table inet "$DNAT_TABLE" 2>/dev/null
  rm -f /tmp/proxy-udp-dnat-ip.cache
  echo "[proxy-udp-dnat] 已清理 DNAT 规则" | systemd-cat -t proxy-udp-dnat -p info 2>/dev/null || true
  echo "已清理 DNAT 规则 (表: $DNAT_TABLE)"
  exit 0
fi

# ============================================================================
# NM dispatcher 过滤: 仅处理目标接口的事件
# ============================================================================
if [[ ! -z "$DEVICE_IP_IFACE" ]]; then
  IFACE_MATCH=0
  for IFACE in ${TRAEFIK_DS_DNAT_IFACES[@]}; do
    if [[ "$DEVICE_IP_IFACE" == "$IFACE" ]]; then
      IFACE_MATCH=1
      break
    fi
  done
  if [[ $IFACE_MATCH -eq 0 ]]; then
    exit 0
  fi
fi

# ============================================================================
# 收集各接口的 IPv4 和 IPv6 地址
# ============================================================================
DNAT_ADDRS_V4=()
DNAT_ADDRS_V6=()
for IFACE in ${TRAEFIK_DS_DNAT_IFACES[@]}; do
  # 收集该接口上所有 IPv4 地址
  while read -r ADDR; do
    if [[ ! -z "$ADDR" ]]; then
      DNAT_ADDRS_V4+=("$ADDR")
    fi
  done < <(ip -4 addr show "$IFACE" 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
  # 收集该接口上所有全局单播 IPv6 (排除 link-local fe80::)
  while read -r ADDR6; do
    if [[ ! -z "$ADDR6" ]]; then
      DNAT_ADDRS_V6+=("$ADDR6")
    fi
  done < <(ip -6 addr show "$IFACE" scope global 2>/dev/null | grep -oP '(?<=inet6\s)[0-9a-fA-F:]+')
done

if [[ ${#DNAT_ADDRS_V4[@]} -eq 0 ]] && [[ ${#DNAT_ADDRS_V6[@]} -eq 0 ]]; then
  echo "[proxy-udp-dnat] 所有接口 (${TRAEFIK_DS_DNAT_IFACES[*]}) 无 IP 地址, 清理旧规则" | systemd-cat -t proxy-udp-dnat -p warning 2>/dev/null || true
  nft delete table inet "$DNAT_TABLE" 2>/dev/null
  exit 0
fi

# ============================================================================
# 检查 IP 是否变化
# ============================================================================
CACHE_FILE="/tmp/proxy-udp-dnat-ip.cache"
CURRENT_ADDRS_STR=$(echo "${DNAT_ADDRS_V4[*]} | ${DNAT_ADDRS_V6[*]}" | tr ' ' '\n' | sort | tr '\n' ' ')
if [[ -f "$CACHE_FILE" ]]; then
  LAST_ADDRS_STR=$(cat "$CACHE_FILE" 2>/dev/null)
  if [[ "$CURRENT_ADDRS_STR" == "$LAST_ADDRS_STR" ]]; then
    echo "[proxy-udp-dnat] IP 未变化 (v4: ${DNAT_ADDRS_V4[*]}, v6: ${DNAT_ADDRS_V6[*]}), 跳过" | systemd-cat -t proxy-udp-dnat -p info 2>/dev/null || true
    exit 0
  fi
fi
echo "$CURRENT_ADDRS_STR" >"$CACHE_FILE"

# ============================================================================
# 构建 nftables 规则 (inet 表族, 同时支持 IPv4 + IPv6)
# ============================================================================
echo "[proxy-udp-dnat] 更新 DNAT: v4=${DNAT_ADDRS_V4[*]} v6=${DNAT_ADDRS_V6[*]} udp ${TRAEFIK_DS_DNAT_PORTS} -> ${TRAEFIK_DS_DNAT_BACKEND}" | systemd-cat -t proxy-udp-dnat -p info 2>/dev/null || true

# 先删旧表 (兼容: 同时尝试删除旧的 ip 表和新的 inet 表)
nft delete table ip "$DNAT_TABLE" 2>/dev/null
nft delete table inet "$DNAT_TABLE" 2>/dev/null

# 构建 IPv4 地址集合
ADDR_SET_V4=""
for ADDR in ${DNAT_ADDRS_V4[@]}; do
  if [[ -z "$ADDR_SET_V4" ]]; then
    ADDR_SET_V4="$ADDR"
  else
    ADDR_SET_V4="$ADDR_SET_V4, $ADDR"
  fi
done

# 构建 IPv6 地址集合
ADDR_SET_V6=""
for ADDR in ${DNAT_ADDRS_V6[@]}; do
  if [[ -z "$ADDR_SET_V6" ]]; then
    ADDR_SET_V6="$ADDR"
  else
    ADDR_SET_V6="$ADDR_SET_V6, $ADDR"
  fi
done

# 构建 nftables 规则文件
NFT_RULES="table inet $DNAT_TABLE {
  chain prerouting {
    type nat hook prerouting priority dstnat; policy accept;"

# IPv4 规则
if [[ ! -z "$ADDR_SET_V4" ]]; then
  NFT_RULES="$NFT_RULES
    meta nfproto ipv4 ip daddr { $ADDR_SET_V4 } udp dport $TRAEFIK_DS_DNAT_PORTS dnat to $TRAEFIK_DS_DNAT_BACKEND"
fi

# IPv6 规则
if [[ ! -z "$ADDR_SET_V6" ]] && [[ ! -z "$TRAEFIK_DS_DNAT_BACKEND_V6" ]]; then
  NFT_RULES="$NFT_RULES
    meta nfproto ipv6 ip6 daddr { $ADDR_SET_V6 } udp dport $TRAEFIK_DS_DNAT_PORTS dnat to $TRAEFIK_DS_DNAT_BACKEND_V6"
fi

NFT_RULES="$NFT_RULES
  }
  chain postrouting {
    type nat hook postrouting priority srcnat; policy accept;"

# IPv4 masquerade
if [[ ! -z "$ADDR_SET_V4" ]]; then
  NFT_RULES="$NFT_RULES
    meta nfproto ipv4 ip daddr $TRAEFIK_DS_DNAT_BACKEND udp dport $TRAEFIK_DS_DNAT_PORTS masquerade"
fi

# IPv6 masquerade
if [[ ! -z "$TRAEFIK_DS_DNAT_BACKEND_V6" ]]; then
  NFT_RULES="$NFT_RULES
    meta nfproto ipv6 ip6 daddr $TRAEFIK_DS_DNAT_BACKEND_V6 udp dport $TRAEFIK_DS_DNAT_PORTS masquerade"
fi

NFT_RULES="$NFT_RULES
  }
}"

echo "$NFT_RULES" | nft -f -

if [[ $? -eq 0 ]]; then
  echo "[proxy-udp-dnat] DNAT 规则已更新" | systemd-cat -t proxy-udp-dnat -p info 2>/dev/null || true
  echo "DNAT 规则已更新:"
  echo "  接口: ${TRAEFIK_DS_DNAT_IFACES[*]}"
  echo "  IPv4: ${DNAT_ADDRS_V4[*]:-无}"
  echo "  IPv6: ${DNAT_ADDRS_V6[*]:-无}"
  echo "  端口: $TRAEFIK_DS_DNAT_PORTS"
  echo "  后端: v4=$TRAEFIK_DS_DNAT_BACKEND v6=${TRAEFIK_DS_DNAT_BACKEND_V6:-未配置}"
  nft list table inet "$DNAT_TABLE"
else
  echo "[proxy-udp-dnat] DNAT 规则更新失败" | systemd-cat -t proxy-udp-dnat -p err 2>/dev/null || true
  echo "Error: DNAT 规则更新失败" >&2
  exit 1
fi
