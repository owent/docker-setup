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

COMPOSE_CONFIGURE=docker-compose.yml
COMPOSE_ENV_FILE=.env
APPFLOWY_VERSION=

if [[ "x$APPFLOWY_ETC_DIR" == "x" ]]; then
  APPFLOWY_ETC_DIR="$RUN_HOME/appflowy/etc"
fi
mkdir -p "$APPFLOWY_ETC_DIR"

if [[ ! -z "$APPFLOWY_UPDATE" ]] || [[ ! -z "$ROUTER_IMAGE_UPDATE" ]] || [[ ! -e "appflowy.version" ]]; then
  GITHUB_TOKEN_ARGS=""
  if [[ ! -z "$GITHUB_TOKEN" ]]; then
    GITHUB_TOKEN_ARGS="-H Authorization: token $GITHUB_TOKEN"
  fi
  APPFLOWY_VERSION=$(curl -L $GITHUB_TOKEN_ARGS 'https://api.github.com/repos/AppFlowy-IO/AppFlowy-Cloud/releases/latest' | grep tag_name | grep -E -o '[0-9]+[0-9\.]+' | head -n 1)
  if [[ -z "$APPFLOWY_VERSION" ]]; then
    echo "Error: Unable to retrieve AppFlowy version"
    exit 1
  fi

  echo $APPFLOWY_VERSION >appflowy.version
else
  APPFLOWY_VERSION=$(cat appflowy.version)
fi

systemctl --user --all | grep -F container-appflowy-cloud.service

if [[ $? -eq 0 ]]; then
  systemctl --user stop container-appflowy-cloud
  systemctl --user disable container-appflowy-cloud
fi

podman-compose -f $COMPOSE_CONFIGURE down

if [[ ! -z "$APPFLOWY_UPDATE" ]] || [[ ! -z "$ROUTER_IMAGE_UPDATE" ]]; then
  podman image prune -a -f --filter "until=240h"
fi

echo "[Unit]
Description=container-appflowy-cloud
After=network.target

[Service]
Type=forking
ExecStart=podman-compose -f $SCRIPT_DIR/$COMPOSE_CONFIGURE up -d
ExecStop=podman-compose -f $SCRIPT_DIR/$COMPOSE_CONFIGURE down

[Install]
WantedBy=multi-user.target
" | tee $APPFLOWY_ETC_DIR/container-appflowy-cloud.service

systemctl --user enable $APPFLOWY_ETC_DIR/container-appflowy-cloud.service
systemctl --user daemon-reload
systemctl --user restart container-appflowy-cloud.service
