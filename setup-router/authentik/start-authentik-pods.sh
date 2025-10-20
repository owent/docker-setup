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

if [[ "x$AUTHENTIK_ETC_DIR" == "x" ]]; then
  AUTHENTIK_ETC_DIR="$RUN_HOME/authentik/etc"
fi
mkdir -p "$AUTHENTIK_ETC_DIR"

if [[ "x$AUTHENTIK_DATA_DIR" == "x" ]]; then
  AUTHENTIK_DATA_DIR="$RUN_HOME/authentik/data"
fi
mkdir -p "$AUTHENTIK_DATA_DIR/media"
mkdir -p "$AUTHENTIK_DATA_DIR/certs"
mkdir -p "$AUTHENTIK_DATA_DIR/custom-templates"

cd "$SCRIPT_DIR"

COMPOSE_CONFIGURE=docker-compose.yml

if [[ ! -z "$AUTHENTIK_UPDATE" ]] || [[ ! -z "$ROUTER_IMAGE_UPDATE" ]]; then
  source "$SCRIPT_DIR/.env"
  podman-compose -f $COMPOSE_CONFIGURE pull
  if [[ $? -ne 0 ]]; then
    echo "Pull $COMPOSE_CONFIGURE failed"
    exit 1
  fi
  podman pull ghcr.io/goauthentik/ldap:${AUTHENTIK_TAG}
  if [[ $? -ne 0 ]]; then
    echo "Pull $COMPOSE_CONFIGURE failed"
    exit 1
  fi
  podman pull ghcr.io/goauthentik/proxy:${AUTHENTIK_TAG}
  if [[ $? -ne 0 ]]; then
    echo "Pull $COMPOSE_CONFIGURE failed"
    exit 1
  fi
  podman pull ghcr.io/goauthentik/rac:${AUTHENTIK_TAG}
  if [[ $? -ne 0 ]]; then
    echo "Pull $COMPOSE_CONFIGURE failed"
    exit 1
  fi
  podman pull ghcr.io/goauthentik/radius:${AUTHENTIK_TAG}
  if [[ $? -ne 0 ]]; then
    echo "Pull $COMPOSE_CONFIGURE failed"
    exit 1
  fi
fi

DOCKER_SOCK_PATH="$XDG_RUNTIME_DIR/podman/podman.sock"
if [[ ! -e "$DOCKER_SOCK_PATH" ]]; then
  if [[ -e "/var/run/docker.sock" ]]; then
    DOCKER_SOCK_PATH="$DOCKER_SOCK_PATH"
  fi
fi
sed -E -i "s;DOCKER_SOCK_PATH=.*;DOCKER_SOCK_PATH=$DOCKER_SOCK_PATH;" "$SCRIPT_DIR/.env"

systemctl --user --all | grep -F container-authentik-server.service

if [[ $? -eq 0 ]]; then
  systemctl --user stop container-authentik-server
  systemctl --user disable container-authentik-server
fi

systemctl --user enable --now podman.socket
systemctl --user start --now podman.socket

podman-compose -f $COMPOSE_CONFIGURE down

if [[ ! -z "$AUTHENTIK_UPDATE" ]] || [[ ! -z "$ROUTER_IMAGE_UPDATE" ]]; then
  podman image prune -a -f --filter "until=240h"
fi

echo "[Unit]
Description=container-authentik-server
After=network.target

[Service]
Type=simple
ExecStart=podman-compose -f $SCRIPT_DIR/$COMPOSE_CONFIGURE up
ExecStop=podman-compose -f $SCRIPT_DIR/$COMPOSE_CONFIGURE down

[Install]
WantedBy=default.target
" | tee $AUTHENTIK_ETC_DIR/container-authentik-server.service

systemctl --user enable $AUTHENTIK_ETC_DIR/container-authentik-server.service
systemctl --user daemon-reload
systemctl --user restart container-authentik-server.service
