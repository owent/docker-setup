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
# SYNCTHING_NETWORK=(internal-frontend)
# SYNCTHING_PUBLISH=($SYNCTHING_CLIENT_LISTEN_PORT:$SYNCTHING_CLIENT_LISTEN_PORT 11000:11000/tcp 11000:11000/udp 11001:11001/tcp 11001:11001/udp)
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
if [[ ! -e "$SYNCTHING_CLIENT_HOME_DIR/data" ]]; then
  mkdir -p "$SYNCTHING_CLIENT_HOME_DIR/data"
  chmod 777 "$SYNCTHING_CLIENT_HOME_DIR"
fi

if [[ "x$SYNCTHING_UPDATE" != "x" ]] && [[ "x$ROUTER_IMAGE_UPDATE" != "x" ]]; then
  podman image pull docker.io/syncthing/syncthing:latest
  if [[ $? -ne 0 ]]; then
    exit 1
  fi
fi

systemctl --user --all | grep -F container-syncthing-client.service

if [[ $? -eq 0 ]]; then
  systemctl --user stop container-syncthing-client
  systemctl --user disable container-syncthing-client
fi

podman container exists syncthing-client

if [[ $? -eq 0 ]]; then
  podman stop syncthing-client
  podman rm -f syncthing-client
fi

SYNCTHING_SERVER_OPTIONS=(
  --home=/syncthing/home/
  --no-port-probing
  --no-browser
  --no-restart
  --no-upgrade
)
SYNCTHING_OPTIONS=(
  -e PUID=$(id -u) -e PGID=$(id -g)
  --userns=keep-id
  --mount "type=bind,source=$SYNCTHING_CLIENT_HOME_DIR,target=/syncthing/home/"
)
if [[ ! -z "$SYNCTHING_NETWORK" ]]; then
  SYNCTHING_NETWORK_HAS_HOST=0
  for network in ${SYNCTHING_NETWORK[@]}; do
    SYNCTHING_OPTIONS+=("--network=$network")
    if [[ "$network" == "host" ]]; then
      SYNCTHING_NETWORK_HAS_HOST=1
    fi
  done
  if [[ ! -z "$SYNCTHING_PUBLISH" ]] && [[ $SYNCTHING_NETWORK_HAS_HOST -eq 0 ]]; then
    for publish in ${SYNCTHING_PUBLISH[@]}; do
      SYNCTHING_OPTIONS+=(-p "$publish")
    done
  else
    SYNCTHING_OPTIONS+=( 
      -p "$SYNCTHING_CLIENT_LISTEN_PORT:$SYNCTHING_CLIENT_LISTEN_PORT"
    )
  fi
else
  SYNCTHING_OPTIONS+=(--network=host)
fi

HAS_MAKE_EXT_DIR=0
for EXT_MOUNTS in ${SYNCTHING_CLIENT_EXT_DIRS[@]}; do
  EXT_MOUNTS_SOURCE="${EXT_MOUNTS/:*/}"
  EXT_MOUNTS_TARGET="${EXT_MOUNTS//*:/}"
  if [[ ! -e "$EXT_MOUNTS_SOURCE" ]]; then
    mkdir -p "$EXT_MOUNTS_SOURCE"
    HAS_MAKE_EXT_DIR=1
  fi
  if [[ ! -e "$SYNCTHING_CLIENT_HOME_DIR/data/$EXT_MOUNTS_TARGET" ]]; then
    mkdir -p "$SYNCTHING_CLIENT_HOME_DIR/data/$EXT_MOUNTS_TARGET"
    HAS_MAKE_EXT_DIR=1
  fi
  SYNCTHING_OPTIONS=(${SYNCTHING_OPTIONS[@]} --mount "type=bind,source=$EXT_MOUNTS_SOURCE,target=/syncthing/home/data/$EXT_MOUNTS_TARGET")
done

if [[ $HAS_MAKE_EXT_DIR -ne 0 ]]; then
  chown $RUN_USER:$RUN_USER -R "$SYNCTHING_CLIENT_HOME_DIR/data"
  chmod 777 -R "$SYNCTHING_CLIENT_HOME_DIR/data"
fi

SYNCTHING_CLIENT_GUI_APIKEY=""
if [[ -e "$RUN_HOME/syncthing/syncthing-client.token.txt" ]]; then
  SYNCTHING_CLIENT_GUI_APIKEY=$(cat "$RUN_HOME/syncthing/syncthing-client.token.txt")
fi
if [[ -z "$SYNCTHING_CLIENT_GUI_APIKEY" ]]; then
  SYNCTHING_CLIENT_GUI_APIKEY=$(head -c 16 /dev/urandom | base64 | tr '/+' '_-' | tr -d '= \n\r')
  echo -n "$SYNCTHING_CLIENT_GUI_APIKEY" > "$RUN_HOME/syncthing/syncthing-client.token.txt"
fi

SYNCTHING_SERVER_OPTIONS+=(
  "--gui-address=$SYNCTHING_CLIENT_GUI_ADDRESS"
  "--gui-apikey=$SYNCTHING_CLIENT_GUI_APIKEY"
)

podman run -d --name syncthing-client --security-opt label=disable \
  ${SYNCTHING_OPTIONS[@]} \
  docker.io/syncthing/syncthing:latest \
  "${SYNCTHING_SERVER_OPTIONS[@]}"

if [[ $? -ne 0 ]]; then
  echo "Failed to start syncthing client container."
  exit 1
fi

if [[ "x$SYNCTHING_UPDATE" != "x" ]] || [[ "x$ROUTER_IMAGE_UPDATE" != "x" ]]; then
  podman image prune -a -f --filter "until=240h"
fi

podman exec syncthing-client ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime

mkdir -p "$SCRIPT_DIR/etc"

podman generate systemd --name syncthing-client | tee "$SCRIPT_DIR/etc/container-syncthing-client.service"

podman stop syncthing-client

systemctl --user enable "$SCRIPT_DIR/etc/container-syncthing-client.service"
systemctl --user restart container-syncthing-client
