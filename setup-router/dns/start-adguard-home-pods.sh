#!/bin/bash

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"

export XDG_RUNTIME_DIR="/run/user/$UID"
export DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR}/bus"

DOCKER_EXEC=$((which podman > /dev/null 2>&1 && echo podman) || (which docker > /dev/null 2>&1 && echo docker))
DOCKER_EXEC_PATH="$(which $DOCKER_EXEC)"

if [[ -z "$RUN_USER" ]]; then
  export RUN_USER=$(id -un)
fi

# sudo loginctl enable-linger $RUN_USER
# $DOCKER_EXEC-compose 在 --network=host 下有兼容性问题
# 非 --network=host 下会导致丢失DNS请求来源信息

if [[ -z "$RUN_USER" ]] || [[ "$RUN_USER" == "root" ]]; then
  echo -e "\033[1;32m$0 can not run with\033[0;m \033[1;31m$RUN_USER\033[0;m"
  exit 1
fi

RUN_HOME=$(awk -F: -v user="$RUN_USER" '$1 == user { print $6 }' /etc/passwd)

if [[ -z "$RUN_HOME" ]]; then
  RUN_HOME="$HOME"
fi

cd "$SCRIPT_DIR"

if [[ -z "$ADGUARD_HOME_ETC_DIR" ]]; then
  ADGUARD_HOME_ETC_DIR="$SCRIPT_DIR/adguard-home-etc"
fi
mkdir -p "$ADGUARD_HOME_ETC_DIR"

if [[ -z "$UNBOUND_ETC_DIR" ]]; then
  UNBOUND_ETC_DIR="$SCRIPT_DIR/unbound-etc"
fi
mkdir -p "$UNBOUND_ETC_DIR"

COMPOSE_CONFIGURE=docker-compose.yml
COMPOSE_ENV_FILE=.env

if [[ ! -z "$ROUTER_IMAGE_UPDATE" ]]; then
  $DOCKER_EXEC-compose -f $COMPOSE_CONFIGURE pull
  if [[ $? -ne 0 ]]; then
    echo "Error: Unable to pull images"
    exit 1
  fi
fi

systemctl --user --all | grep -F container-adguard-home.service

if [[ $? -eq 0 ]]; then
  systemctl --user stop container-adguard-home
  systemctl --user disable container-adguard-home
fi

$DOCKER_EXEC-compose -f $COMPOSE_CONFIGURE down

if [[ ! -z "$ROUTER_IMAGE_UPDATE" ]]; then
  $DOCKER_EXEC image prune -a -f --filter "until=240h"
fi

echo "[Unit]
Description=container-adguard-home
After=network.target

[Service]
Type=simple
ExecStart=$DOCKER_EXEC-compose -f $SCRIPT_DIR/$COMPOSE_CONFIGURE up
ExecStop=$DOCKER_EXEC-compose -f $SCRIPT_DIR/$COMPOSE_CONFIGURE down

[Install]
WantedBy=default.target
" | tee $ADGUARD_HOME_ETC_DIR/container-adguard-home.service

systemctl --user enable $ADGUARD_HOME_ETC_DIR/container-adguard-home.service
systemctl --user daemon-reload
systemctl --user restart container-adguard-home.service
