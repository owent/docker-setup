#!/bin/bash

# ============================================================================
# Traefik 反向代理容器服务脚本 (支持 Quadlet)
# ============================================================================
# 参考: haproxy/create-haproxy-systemd.sh, caddy/create-proxy-pod.sh
#
# 并发负载 vs CPU/内存 大致关系 (仅供参考，实际依赖于后端响应和流量类型):
# -----------------------------------------------------------------------
# | 并发连接数    | CPU 核心 | 内存     | 适用场景                          |
# |-------------|---------|---------|----------------------------------|
# | 100-500     | 1 vCPU  | 128MB   | 小型服务/开发环境                   |
# | 500-2000    | 2 vCPU  | 256MB   | 中小型生产环境                     |
# | 2000-5000   | 2-4 vCPU| 512MB   | 中型生产环境/API网关                |
# | 5000-10000  | 4-8 vCPU| 1GB     | 大型生产环境                       |
# | 10000-50000 | 8+ vCPU | 2-4GB   | 高并发场景(含大文件/长连接)           |
# -----------------------------------------------------------------------
# 注意: Git LFS 大文件下载、长连接(WebSocket) 等场景会显著增加内存占用。
#       启用缓存中间件时内存消耗会随缓存量增长。
#       建议通过 Traefik dashboard/metrics 监控实际资源使用情况。
# ============================================================================

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"

if [[ -e "$(dirname "$SCRIPT_DIR")/configure-router.sh" ]]; then
  source "$(dirname "$SCRIPT_DIR")/configure-router.sh"
fi

export XDG_RUNTIME_DIR="/run/user/$UID"
export DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR}/bus"

if [[ -z "$RUN_USER" ]]; then
  export RUN_USER=$(id -un)
fi

RUN_HOME=$(awk -F: -v user="$RUN_USER" '$1 == user { print $6 }' /etc/passwd)

if [[ -z "$RUN_HOME" ]]; then
  RUN_HOME="$HOME"
fi

cd "$SCRIPT_DIR"

# ============================================================================
# 可配置变量 (可在 configure-router.sh 或环境变量中覆盖)
# ============================================================================

# 镜像地址
if [[ -z "$TRAEFIK_IMAGE" ]]; then
  TRAEFIK_IMAGE="traefik:v3"
fi

# 配置目录
if [[ -z "$TRAEFIK_ETC_DIR" ]]; then
  TRAEFIK_ETC_DIR="$SCRIPT_DIR/etc"
fi

# 数据目录（ACME证书等持久化数据）
if [[ -z "$TRAEFIK_DATA_DIR" ]]; then
  TRAEFIK_DATA_DIR="$SCRIPT_DIR/data"
fi

# 日志目录
if [[ -z "$TRAEFIK_LOG_DIR" ]]; then
  TRAEFIK_LOG_DIR="$SCRIPT_DIR/log"
fi

# 网络配置 (默认使用 host 网络)
# TRAEFIK_NETWORK=(host)
# TRAEFIK_NETWORK=(internal-frontend internal-backend)

# 端口映射 (仅非 host 网络时有效)
# TRAEFIK_PUBLISH=(80:80 443:443/tcp 443:443/udp 6041:6041)

# SSL 证书目录
# TRAEFIK_SSL_DIR=/path/to/ssl/certs

# 自定义 DNS (覆盖系统DNS解析器, 支持 IPv4 和 IPv6)
# TRAEFIK_DNS=(119.29.29.29 223.5.5.5 "2402:4e00::1")

# UDP entryPoint 绑定 IP (多网卡场景, 防止回包源 IP 不一致)
# 设置后会通过环境变量覆盖 traefik.yml 中 udp-generic 的 address
# 支持格式:
#   固定 IP:        TRAEFIK_UDP_BIND_IP="10.64.0.1"
#   自动检测网卡 IP: TRAEFIK_UDP_BIND_IP="auto:eth0"
# TRAEFIK_UDP_BIND_IP="auto:eth0"

# ============================================================================
# 目录初始化
# ============================================================================
mkdir -p "$TRAEFIK_ETC_DIR"
mkdir -p "$TRAEFIK_ETC_DIR/dynamic"
mkdir -p "$TRAEFIK_DATA_DIR"
mkdir -p "$TRAEFIK_LOG_DIR"

# 复制默认配置文件（如果不存在）
if [[ ! -f "$TRAEFIK_ETC_DIR/traefik.yml" ]]; then
  if [[ -f "$SCRIPT_DIR/etc/traefik.yml" ]]; then
    echo "配置文件 $TRAEFIK_ETC_DIR/traefik.yml 已存在，跳过复制"
  else
    echo "警告: 未找到 traefik.yml 静态配置文件，请先创建"
  fi
fi

# ============================================================================
# 判断 systemd 服务目录 (root vs 普通用户)
# ============================================================================
if [[ "root" == "$(id -un)" ]]; then
  SYSTEMD_SERVICE_DIR=/lib/systemd/system
  SYSTEMD_CONTAINER_DIR=/etc/containers/systemd/
  mkdir -p "$SYSTEMD_CONTAINER_DIR"
else
  SYSTEMD_SERVICE_DIR="$HOME/.config/systemd/user"
  SYSTEMD_CONTAINER_DIR="$HOME/.config/containers/systemd"
  mkdir -p "$SYSTEMD_SERVICE_DIR"
  mkdir -p "$SYSTEMD_CONTAINER_DIR"
fi

# ============================================================================
# 镜像更新
# ============================================================================
if [[ ! -z "$TRAEFIK_UPDATE" ]] || [[ ! -z "$ROUTER_IMAGE_UPDATE" ]]; then
  podman pull "$TRAEFIK_IMAGE"
  if [[ $? -ne 0 ]]; then
    echo "Error: 拉取镜像 $TRAEFIK_IMAGE 失败"
    exit 1
  fi
fi

# ============================================================================
# 停止并清理旧容器/服务
# ============================================================================
if [[ "$SYSTEMD_SERVICE_DIR" == "/lib/systemd/system" ]]; then
  systemctl --all | grep -F proxy-traefik.service >/dev/null 2>&1
  if [[ $? -eq 0 ]]; then
    systemctl stop proxy-traefik.service
    systemctl disable proxy-traefik.service
  fi
else
  systemctl --user --all | grep -F proxy-traefik.service >/dev/null 2>&1
  if [[ $? -eq 0 ]]; then
    systemctl --user stop proxy-traefik.service
    systemctl --user disable proxy-traefik.service
  fi
fi

podman container inspect proxy-traefik >/dev/null 2>&1
if [[ $? -eq 0 ]]; then
  podman stop proxy-traefik
  podman rm -f proxy-traefik
fi

if [[ ! -z "$TRAEFIK_UPDATE" ]] || [[ ! -z "$ROUTER_IMAGE_UPDATE" ]]; then
  podman image prune -a -f --filter "until=240h"
fi

# ============================================================================
# 构建容器运行参数
# ============================================================================
TRAEFIK_OPTIONS=(
  -e "TZ=Asia/Shanghai"
  --cap-add=NET_ADMIN
  --cap-add=NET_BIND_SERVICE
  --mount "type=bind,source=$TRAEFIK_ETC_DIR/traefik.yml,target=/etc/traefik/traefik.yml,readonly"
  --mount "type=bind,source=$TRAEFIK_ETC_DIR/dynamic,target=/etc/traefik/dynamic,readonly"
  --mount "type=bind,source=$TRAEFIK_DATA_DIR,target=/data/traefik"
  --mount "type=bind,source=$TRAEFIK_LOG_DIR,target=/var/log/traefik"
)

# 挂载 SSL 证书目录
if [[ ! -z "$TRAEFIK_SSL_DIR" ]]; then
  TRAEFIK_OPTIONS+=(--mount "type=bind,source=$TRAEFIK_SSL_DIR,target=/etc/traefik/ssl,readonly")
fi

# 自定义 DNS (覆盖容器内 /etc/resolv.conf)
if [[ ! -z "$TRAEFIK_DNS" ]]; then
  for dns_server in ${TRAEFIK_DNS[@]}; do
    TRAEFIK_OPTIONS+=(--dns "$dns_server")
  done
fi

# UDP entryPoint 绑定 IP (多网卡场景: 固定回包源 IP)
if [[ ! -z "$TRAEFIK_UDP_BIND_IP" ]]; then
  UDP_BIND_ADDR="$TRAEFIK_UDP_BIND_IP"
  # 支持 auto:<interface> 格式，自动获取指定网卡的 IPv4 地址
  if [[ "$UDP_BIND_ADDR" == auto:* ]]; then
    UDP_IFACE="${UDP_BIND_ADDR#auto:}"
    UDP_BIND_ADDR=$(ip -4 addr show "$UDP_IFACE" 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)
    if [[ -z "$UDP_BIND_ADDR" ]]; then
      echo "警告: 无法从网卡 $UDP_IFACE 获取 IPv4 地址，UDP entryPoint 将绑定所有接口"
    fi
  fi
  if [[ ! -z "$UDP_BIND_ADDR" ]]; then
    # 通过环境变量覆盖 traefik.yml 中 udp-generic 的 address
    TRAEFIK_OPTIONS+=(-e "TRAEFIK_ENTRYPOINTS_UDP__GENERIC_ADDRESS=${UDP_BIND_ADDR}:5353/udp")
    echo "UDP entryPoint 绑定到: ${UDP_BIND_ADDR}:5353/udp"
  fi
fi

# 网络配置
TRAEFIK_HAS_HOST_NETWORK=0
if [[ ! -z "$TRAEFIK_NETWORK" ]]; then
  for network in ${TRAEFIK_NETWORK[@]}; do
    TRAEFIK_OPTIONS+=("--network=$network")
    if [[ "$network" == "host" ]]; then
      TRAEFIK_HAS_HOST_NETWORK=1
    fi
  done
  if [[ ! -z "$TRAEFIK_PUBLISH" ]] && [[ $TRAEFIK_HAS_HOST_NETWORK -eq 0 ]]; then
    for publish in ${TRAEFIK_PUBLISH[@]}; do
      TRAEFIK_OPTIONS+=(-p "$publish")
    done
  fi
else
  TRAEFIK_OPTIONS+=(--network=host)
fi

# ============================================================================
# 使用 podlet 生成 Quadlet 配置 或 回退到传统 systemd 方式
# ============================================================================
PODLET_IMAGE_URL="ghcr.io/containers/podlet:latest"
PODLET_RUN=($(which podlet 2>/dev/null))
FIND_PODLET_RESULT=$?
if [[ $FIND_PODLET_RESULT -ne 0 ]]; then
  (podman image inspect "$PODLET_IMAGE_URL" > /dev/null 2>&1 || podman pull "$PODLET_IMAGE_URL") && FIND_PODLET_RESULT=0 && PODLET_RUN=(podman run --rm "$PODLET_IMAGE_URL")
fi

if [[ $FIND_PODLET_RESULT -eq 0 ]]; then
  PODLET_OPTIONS=(--install --wanted-by default.target --wants network-online.target --after network-online.target)
  for network in ${TRAEFIK_NETWORK[@]}; do
    if [[ -e "$HOME/.config/containers/systemd/$network.network" ]]; then
      PODLET_OPTIONS+=(--after "$network-network.service" --wants "$network-network.service")
    fi
  done
  ${PODLET_RUN[@]} "${PODLET_OPTIONS[@]}" \
    podman run -d --name proxy-traefik --security-opt label=disable \
    "${TRAEFIK_OPTIONS[@]}" \
    "$TRAEFIK_IMAGE" | tee -p "$SYSTEMD_CONTAINER_DIR/proxy-traefik.container"
else
  podman run -d --name proxy-traefik --security-opt label=disable \
    "${TRAEFIK_OPTIONS[@]}" \
    "$TRAEFIK_IMAGE"

  if [[ $? -ne 0 ]]; then
    echo "Error: 启动 traefik 容器失败"
    exit 1
  fi

  podman generate systemd proxy-traefik | tee -p "$SYSTEMD_SERVICE_DIR/proxy-traefik.service"
  podman container stop proxy-traefik
fi

# ============================================================================
# 启用并启动 systemd 服务
# ============================================================================
if [[ "$SYSTEMD_SERVICE_DIR" == "/lib/systemd/system" ]]; then
  systemctl daemon-reload
  if [[ $FIND_PODLET_RESULT -ne 0 ]]; then
    systemctl enable proxy-traefik.service
  fi
  systemctl start proxy-traefik.service
else
  systemctl --user daemon-reload
  if [[ $FIND_PODLET_RESULT -ne 0 ]]; then
    systemctl --user enable proxy-traefik.service
  fi
  systemctl --user start proxy-traefik.service
fi

echo "Traefik 服务已启动"
echo "  配置目录: $TRAEFIK_ETC_DIR"
echo "  数据目录: $TRAEFIK_DATA_DIR"
echo "  日志目录: $TRAEFIK_LOG_DIR"
echo "  Dashboard: http://localhost:6401 (需在 traefik.yml 中启用)"
