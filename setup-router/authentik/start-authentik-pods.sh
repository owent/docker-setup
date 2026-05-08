#!/bin/bash

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"

export XDG_RUNTIME_DIR="/run/user/$UID"
export DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR}/bus"

DOCKER_EXEC=$((which podman > /dev/null 2>&1 && echo podman) || (which docker > /dev/null 2>&1 && echo docker))

if [[ -z "$RUN_USER" ]]; then
  export RUN_USER=$(id -un)
fi

# sudo loginctl enable-linger $RUN_USER

if [[ -z "$RUN_USER" ]] || [[ "$RUN_USER" == "root" ]]; then
  echo -e "\033[1;32m$0 can not run with\033[0;m \033[1;31m$RUN_USER\033[0;m"
  exit 1
fi

if [[ "x$AUTHENTIK_ETC_DIR" == "x" ]]; then
  AUTHENTIK_ETC_DIR="$SCRIPT_DIR/etc"
fi
mkdir -p "$AUTHENTIK_ETC_DIR"

if [[ "x$AUTHENTIK_DATA_DIR" == "x" ]]; then
  AUTHENTIK_DATA_DIR="$SCRIPT_DIR/data"
fi
mkdir -p "$AUTHENTIK_DATA_DIR/media"
mkdir -p "$AUTHENTIK_DATA_DIR/certs"
mkdir -p "$AUTHENTIK_DATA_DIR/custom-templates"

cd "$SCRIPT_DIR"

COMPOSE_CONFIGURE=docker-compose.yaml

if [[ ! -z "$AUTHENTIK_UPDATE" ]] || [[ ! -z "$ROUTER_IMAGE_UPDATE" ]]; then
  source "$SCRIPT_DIR/.env"
  $DOCKER_EXEC-compose -f $COMPOSE_CONFIGURE pull
  if [[ $? -ne 0 ]]; then
    echo "Pull $COMPOSE_CONFIGURE failed"
    exit 1
  fi
  $DOCKER_EXEC pull ghcr.io/goauthentik/ldap:${AUTHENTIK_TAG}
  if [[ $? -ne 0 ]]; then
    echo "Pull $COMPOSE_CONFIGURE failed"
    exit 1
  fi
  $DOCKER_EXEC pull ghcr.io/goauthentik/proxy:${AUTHENTIK_TAG}
  if [[ $? -ne 0 ]]; then
    echo "Pull $COMPOSE_CONFIGURE failed"
    exit 1
  fi
  $DOCKER_EXEC pull ghcr.io/goauthentik/rac:${AUTHENTIK_TAG}
  if [[ $? -ne 0 ]]; then
    echo "Pull $COMPOSE_CONFIGURE failed"
    exit 1
  fi
  $DOCKER_EXEC pull ghcr.io/goauthentik/radius:${AUTHENTIK_TAG}
  if [[ $? -ne 0 ]]; then
    echo "Pull $COMPOSE_CONFIGURE failed"
    exit 1
  fi
fi

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

DOCKER_SOCK_PATH="$XDG_RUNTIME_DIR/$DOCKER_EXEC/$DOCKER_EXEC.sock"
if [[ ! -e "$DOCKER_SOCK_PATH" ]]; then
  if [[ -e "/var/run/docker.sock" ]]; then
    DOCKER_SOCK_PATH="$DOCKER_SOCK_PATH"
  fi
fi
sed -E -i "s;DOCKER_SOCK_PATH=.*;DOCKER_SOCK_PATH=$DOCKER_SOCK_PATH;" "$SCRIPT_DIR/.env"

systemctl --user --all | grep -F container-authentik.service

if [[ $? -eq 0 ]]; then
  systemctl --user stop container-authentik
  systemctl --user disable container-authentik
fi

systemctl --user enable --now $DOCKER_EXEC.socket
systemctl --user start --now $DOCKER_EXEC.socket

$DOCKER_EXEC-compose -f $COMPOSE_CONFIGURE down

if [[ ! -z "$AUTHENTIK_UPDATE" ]] || [[ ! -z "$ROUTER_IMAGE_UPDATE" ]]; then
  $DOCKER_EXEC image prune -a -f --filter "until=240h"
fi

echo "[Unit]
Description=container-authentik
Wants=network-online.target
After=network-online.target internal-backend-network.service internal-frontend-network.service

[Service]
Type=simple
ExecStart=$DOCKER_EXEC-compose -f $SCRIPT_DIR/$COMPOSE_CONFIGURE up
ExecStop=$DOCKER_EXEC-compose -f $SCRIPT_DIR/$COMPOSE_CONFIGURE down

[Install]
WantedBy=default.target
" | tee $SYSTEMD_SERVICE_DIR/container-authentik.service

systemctl --user enable container-authentik.service
systemctl --user daemon-reload
systemctl --user restart container-authentik.service
