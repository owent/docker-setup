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

if [[ "x$AFFINE_ETC_DIR" == "x" ]]; then
  AFFINE_ETC_DIR="$RUN_HOME/appflowy/etc"
fi
mkdir -p "$AFFINE_ETC_DIR"

cd "$SCRIPT_DIR"

COMPOSE_CONFIGURE=docker-compose.yml
COMPOSE_ENV_FILE=.env

if [[ ! -z "$AFFINE_UPDATE" ]] || [[ ! -z "$ROUTER_IMAGE_UPDATE" ]]; then
  podman-compose -f $COMPOSE_CONFIGURE pull
  if [[ $? -ne 0 ]]; then
    echo "Pull $COMPOSE_CONFIGURE failed"
    exit 1
  fi
fi

systemctl --user --all | grep -F container-affine-server.service

if [[ $? -eq 0 ]]; then
  systemctl --user stop container-affine-server
  systemctl --user disable container-affine-server
fi

podman-compose -f $COMPOSE_CONFIGURE down

sed -i -E "s;^[[:space:]]*CONFIG_LOCATION=.*;CONFIG_LOCATION=$AFFINE_ETC_DIR;g" $COMPOSE_CONFIGURE

if [[ ! -z "$AFFINE_UPDATE" ]] || [[ ! -z "$ROUTER_IMAGE_UPDATE" ]]; then
  podman image prune -a -f --filter "until=240h"
fi

echo "[Unit]
Description=container-affine-server
After=network.target

[Service]
Type=simple
ExecStart=podman-compose -f $SCRIPT_DIR/$COMPOSE_CONFIGURE up
ExecStop=podman-compose -f $SCRIPT_DIR/$COMPOSE_CONFIGURE down

[Install]
WantedBy=default.target
" | tee $AFFINE_ETC_DIR/container-affine-server.service

systemctl --user enable $AFFINE_ETC_DIR/container-affine-server.service
systemctl --user daemon-reload
systemctl --user restart container-affine-server.service
