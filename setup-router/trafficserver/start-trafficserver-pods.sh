#!/bin/bash

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"

export XDG_RUNTIME_DIR="/run/user/$UID"
export DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR}/bus"

if [[ -z "$RUN_USER" ]]; then
  export RUN_USER=$(id -un)
fi

# sudo loginctl enable-linger $RUN_USER

if [[ -z "$RUN_USER" ]] || [[ "$RUN_USER" == "root" ]]; then
  echo -e "\033[1;32m$0 can not run with\033[0;m \033[1;31m$RUN_USER\033[0;m"
  exit 1
fi

RUN_HOME=$(awk -F: -v user="$RUN_USER" '$1 == user { print $6 }' /etc/passwd)

if [[ -z "$RUN_HOME" ]]; then
  RUN_HOME="$HOME"
fi

cd "$SCRIPT_DIR"

if [[ -e "$SCRIPT_DIR/.env" ]]; then
  source "$SCRIPT_DIR/.env"
fi

# 配置目录 (可通过环境变量覆盖)
if [[ -z "$TRAFFICSERVER_ETC_DIR" ]]; then
  TRAFFICSERVER_ETC_DIR="$SCRIPT_DIR/etc"
fi

# 缓存目录 (可通过环境变量覆盖)
if [[ -z "$TRAFFICSERVER_CACHE_DIR" ]]; then
  TRAFFICSERVER_CACHE_DIR="$SCRIPT_DIR/cache"
fi

# 日志目录 (可通过环境变量覆盖)
if [[ -z "$TRAFFICSERVER_LOG_DIR" ]]; then
  TRAFFICSERVER_LOG_DIR="$SCRIPT_DIR/logs"
fi

mkdir -p "$TRAFFICSERVER_ETC_DIR"
mkdir -p "$TRAFFICSERVER_CACHE_DIR"
mkdir -p "$TRAFFICSERVER_LOG_DIR"
chmod 777 "$TRAFFICSERVER_LOG_DIR"

# 导出环境变量供 docker-compose 使用
export TRAFFICSERVER_ETC_DIR
export TRAFFICSERVER_CACHE_DIR
export TRAFFICSERVER_LOG_DIR

COMPOSE_CONFIGURE=docker-compose.yml

# 确保网络存在
for NETWORK_NAME in internal-backend internal-frontend; do
  podman network exists $NETWORK_NAME 2>/dev/null
  if [[ $? -ne 0 ]]; then
    echo "Creating network: $NETWORK_NAME"
    podman network create $NETWORK_NAME
  fi
done

if [[ ! -z "$ROUTER_IMAGE_UPDATE" ]]; then
  podman-compose -f $COMPOSE_CONFIGURE pull
  if [[ $? -ne 0 ]]; then
    echo "Error: Unable to pull images"
    # 继续执行，可能需要本地构建
  fi
  podman-compose -f $COMPOSE_CONFIGURE build
  if [[ $? -ne 0 ]]; then
    echo "Error: Unable to build images"
    exit 1
  fi
fi

systemctl --user --all | grep -F container-trafficserver.service

if [[ $? -eq 0 ]]; then
  systemctl --user stop container-trafficserver
  systemctl --user disable container-trafficserver
fi

podman-compose -f $COMPOSE_CONFIGURE down

if [[ ! -z "$ROUTER_IMAGE_UPDATE" ]]; then
  podman image prune -a -f --filter "until=240h"
fi

echo "[Unit]
Description=container-trafficserver
After=network.target

[Service]
Type=simple
ExecStart=$(which podman-compose) -f $SCRIPT_DIR/$COMPOSE_CONFIGURE up
ExecStop=$(which podman-compose) -f $SCRIPT_DIR/$COMPOSE_CONFIGURE down

[Install]
WantedBy=default.target
" | tee $TRAFFICSERVER_ETC_DIR/container-trafficserver.service

systemctl --user enable $TRAFFICSERVER_ETC_DIR/container-trafficserver.service
systemctl --user daemon-reload
systemctl --user restart container-trafficserver.service

echo ""
echo "========================================"
echo "Traffic Server started successfully!"
echo "Service: container-trafficserver"
echo "Listening port: 3126"
echo "Config directory: $TRAFFICSERVER_ETC_DIR"
echo "Cache directory: $TRAFFICSERVER_CACHE_DIR"
echo "Log directory: $TRAFFICSERVER_LOG_DIR"
echo "========================================"
echo ""
echo "Check status: systemctl --user status container-trafficserver"
echo "View logs: journalctl --user -u container-trafficserver -f"
