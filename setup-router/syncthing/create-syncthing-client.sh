#!/bin/bash

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"

if [[ -e "$(dirname "$SCRIPT_DIR")/configure-router.sh" ]]; then
  source "$(dirname "$SCRIPT_DIR")/configure-router.sh"
elif [[ -e "$SCRIPT_DIR/configure-server.sh" ]]; then
  source "$SCRIPT_DIR/configure-server.sh"
fi

export XDG_RUNTIME_DIR="/run/user/$UID"
export DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR}/bus"

RUN_USER=$(id -un)
# sudo loginctl enable-linger $RUN_USER

if [[ "x$RUN_USER" == "x" ]] || [[ "x$RUN_USER" == "xroot" ]]; then
  echo -e "\033[1;32m$0 can not run with\033[0;m \033[1;31m$RUN_USER\033[0;m"
  exit 1
fi

RUN_HOME=$(cat /etc/passwd | awk "BEGIN{FS=\":\"} \$1 == \"$RUN_USER\" { print \$6 }")

if [[ "x$RUN_HOME" == "x" ]]; then
  RUN_HOME="$HOME"
fi

if [[ "x$SYNCTHING_CLIENT_HOME_DIR" == "x" ]]; then
  SYNCTHING_CLIENT_HOME_DIR="$RUN_HOME/syncthing/home"
fi
mkdir -p "$SYNCTHING_CLIENT_HOME_DIR"
chmod 777 "$SYNCTHING_CLIENT_HOME_DIR"

if [[ "x$SYNCTHING_SSL_DIR" == "x" ]]; then
  SYNCTHING_SSL_DIR="$RUN_HOME/syncthing/ssl/"
fi
mkdir -p "$SYNCTHING_SSL_DIR"
chmod 777 "$SYNCTHING_SSL_DIR"

if [[ "x$SYNCTHING_SSL_CERT" == "x" ]]; then
  SYNCTHING_SSL_CERT="$SYNCTHING_SSL_DIR/cert.pem"
fi

if [[ "x$SYNCTHING_SSL_KEY" == "x" ]]; then
  SYNCTHING_SSL_KEY="$SYNCTHING_SSL_DIR/key.pem"
fi

systemctl --user --all | grep -F container-syncthing-client.service

if [[ $? -eq 0 ]]; then
  systemctl --user stop container-syncthing-client
  systemctl --user disable container-syncthing-client
fi

podman container inspect syncthing-client >/dev/null 2>&1

if [[ $? -eq 0 ]]; then
  podman stop syncthing-client
  podman rm -f syncthing-client
fi

if [[ "x$SYNCTHING_UPDATE" != "x" ]]; then
  podman image inspect docker.io/syncthing/syncthing:latest >/dev/null 2>&1
  if [[ $? -eq 0 ]]; then
    podman image rm -f docker.io/syncthing/syncthing:latest
  fi
fi

podman pull docker.io/syncthing/syncthing:latest

if [[ -e "$SYNCTHING_SSL_CERT" ]] && [[ -e "$SYNCTHING_SSL_KEY" ]]; then
  SYNCTHING_SSL_OPTIONS=(-keys=/syncthing/ssl)
else
  SYNCTHING_SSL_OPTIONS=()
fi
SYNCTHING_MOUNT_DIRS=(
  --mount "type=bind,source=$SYNCTHING_SSL_DIR,target=/syncthing/ssl/"
  --mount "type=bind,source=$SYNCTHING_CLIENT_HOME_DIR,target=/syncthing/home/"
)
for EXT_MOUNTS in ${SYNCTHING_CLIENT_EXT_DIRS[@]}; do
  EXT_MOUNTS_SOURCE="${EXT_MOUNTS/:*/}"
  EXT_MOUNTS_TARGET="${EXT_MOUNTS//*:/}"
  mkdir -p "$EXT_MOUNTS_SOURCE"
  SYNCTHING_MOUNT_DIRS=(${SYNCTHING_MOUNT_DIRS[@]} --mount "type=bind,source=$EXT_MOUNTS_SOURCE,target=/syncthing/home/data/$EXT_MOUNTS_TARGET")
done

SYNCTHING_CLIENT_GUI_APIKEY=""
if [[ -e "$SCRIPT_DIR/.syncthing-client.token" ]]; then
  SYNCTHING_CLIENT_GUI_APIKEY=$(cat "$SCRIPT_DIR/.syncthing-client.token")
fi
if [[ -z "$SYNCTHING_CLIENT_GUI_APIKEY" ]]; then
  SYNCTHING_CLIENT_GUI_APIKEY=$(openssl rand -base64 15 | tr '/' '_' | tr '+' '-')
fi

podman run -d --name syncthing-client --security-opt label=disable \
  ${SYNCTHING_MOUNT_DIRS[@]} \
  --network=host \
  docker.io/syncthing/syncthing:latest \
  ${SYNCTHING_SSL_OPTIONS[@]} \
  --home=/syncthing/home/ \
  --no-default-folder \
  --skip-port-probing \
  "--gui-address=$SYNCTHING_CLIENT_GUI_ADDRESS" \
  "--gui-apikey=$SYNCTHING_CLIENT_GUI_APIKEY" \
  --no-browser \
  --no-restart \
  --no-upgrade

podman exec syncthing-client ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime

mkdir -p "$SCRIPT_DIR/etc"

podman generate systemd --name syncthing-client | tee "$SCRIPT_DIR/etc/container-syncthing-client.service"

podman stop syncthing-client

systemctl --user enable "$SCRIPT_DIR/etc/container-syncthing-client.service"
systemctl --user restart container-syncthing-client
