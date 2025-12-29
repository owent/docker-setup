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

if [[ -z "$CADDY_ETC_DIR" ]]; then
  CADDY_ETC_DIR="$SCRIPT_DIR/etc"
fi
mkdir -p "$CADDY_ETC_DIR"

COMPOSE_CONFIGURE=docker-compose.yml
COMPOSE_ENV_FILE=.env

if [[ ! -z "$ROUTER_IMAGE_UPDATE" ]]; then
  podman-compose -f $COMPOSE_CONFIGURE pull
  if [[ $? -ne 0 ]]; then
    echo "Error: Unable to pull images"
    exit 1
  fi
  podman-compose -f $COMPOSE_CONFIGURE build
  if [[ $? -ne 0 ]]; then
    echo "Error: Unable to build images"
    exit 1
  fi
fi

if [[ $? -eq 0 ]]; then
  podman exec caddy caddy validate --config /etc/caddy/Caddyfile 2>/dev/null
  if [[ $? -ne 0 ]]; then
    echo "Caddyfile validation failed"
    exit 1
  fi
fi

systemctl --user --all | grep -F container-caddy.service

if [[ $? -eq 0 ]]; then
  systemctl --user stop container-caddy
  systemctl --user disable container-caddy
fi

podman-compose -f $COMPOSE_CONFIGURE down

if [[ ! -z "$ROUTER_IMAGE_UPDATE" ]]; then
  podman image prune -a -f --filter "until=240h"
fi

echo "[Unit]
Description=container-caddy
After=network.target

[Service]
Type=simple
ExecStart=podman-compose -f $SCRIPT_DIR/$COMPOSE_CONFIGURE up
ExecStop=podman-compose -f $SCRIPT_DIR/$COMPOSE_CONFIGURE down

[Install]
WantedBy=default.target
" | tee $CADDY_ETC_DIR/container-caddy.service

systemctl --user enable $CADDY_ETC_DIR/container-caddy.service
systemctl --user daemon-reload
systemctl --user restart container-caddy.service
