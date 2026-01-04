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

if [[ -z "$HAPROXY_ETC_DIR" ]]; then
  HAPROXY_ETC_DIR="$SCRIPT_DIR/etc"
fi
mkdir -p "$HAPROXY_ETC_DIR"

COMPOSE_CONFIGURE=docker-compose.yml
COMPOSE_ENV_FILE=.env

if [[ ! -z "$ROUTER_IMAGE_UPDATE" ]]; then
  podman-compose -f $COMPOSE_CONFIGURE pull
  if [[ $? -ne 0 ]]; then
    echo "Error: Unable to pull images"
    exit 1
  fi
fi

systemctl --user --all | grep -F container-haproxy.service

if [[ $? -eq 0 ]]; then
  systemctl --user stop container-haproxy
  systemctl --user disable container-haproxy
fi

podman-compose -f $COMPOSE_CONFIGURE down

if [[ ! -z "$ROUTER_IMAGE_UPDATE" ]]; then
  podman image prune -a -f --filter "until=240h"
fi

echo "[Unit]
Description=container-haproxy
After=network.target

[Service]
Type=simple
ExecStart=podman-compose -f $SCRIPT_DIR/$COMPOSE_CONFIGURE up
ExecStop=podman-compose -f $SCRIPT_DIR/$COMPOSE_CONFIGURE down

[Install]
WantedBy=default.target
" | tee $HAPROXY_ETC_DIR/container-haproxy.service

systemctl --user enable $HAPROXY_ETC_DIR/container-haproxy.service
systemctl --user daemon-reload
systemctl --user restart container-haproxy.service

# 设置 HAProxy 监控
if [[ -f "$RUN_HOME/.config/haproxy-monitor.env" ]]; then
  MONITOR_CONFIG_DIR="$RUN_HOME/.config/haproxy"
  mkdir -p "$MONITOR_CONFIG_DIR"

  # 复制监控脚本
  cp -f "$SCRIPT_DIR/monitor-haproxy.sh" "$MONITOR_CONFIG_DIR/"
  chmod +x "$MONITOR_CONFIG_DIR/monitor-haproxy.sh"

  # 安装监控服务
  cp -f "$SCRIPT_DIR/haproxy-monitor.service" "$RUN_HOME/.config/systemd/user/"
  cp -f "$SCRIPT_DIR/haproxy-monitor.timer" "$RUN_HOME/.config/systemd/user/"

  systemctl --user daemon-reload
  systemctl --user enable haproxy-monitor.timer
  systemctl --user restart haproxy-monitor.timer

  echo "HAProxy 监控服务已部署，请配置 $RUN_HOME/.config/haproxy-monitor.env"
fi