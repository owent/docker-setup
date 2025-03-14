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

if [[ "x$SYNCTHING_RELAY_SERVER_LISTEN_PORT" == "x" ]]; then
  SYNCTHING_RELAY_SERVER_LISTEN_PORT=6349
fi

if [[ "x$SYNCTHING_RELAY_SERVER_STATUS_PORT" == "x" ]]; then
  SYNCTHING_RELAY_SERVER_STATUS_PORT=6350
fi

if [[ "x$SYNCTHING_ETC_DIR" == "x" ]]; then
  SYNCTHING_ETC_DIR="$RUN_HOME/syncthing/etc"
fi
mkdir -p "$SYNCTHING_ETC_DIR"
chmod 777 "$SYNCTHING_ETC_DIR"

if [[ "x$SYNCTHING_DATA_DIR" == "x" ]]; then
  SYNCTHING_DATA_DIR="$RUN_HOME/syncthing/data"
fi
mkdir -p "$SYNCTHING_DATA_DIR"
chmod 777 "$SYNCTHING_DATA_DIR"

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

if [[ "x$SYNCTHING_UPDATE" != "x" ]] && [[ "x$ROUTER_IMAGE_UPDATE" != "x" ]]; then
  podman pull exists docker.io/syncthing/relaysrv:latest
  if [[ $? -ne 0 ]]; then
    exit 1
  fi
fi

systemctl --user --all | grep -F container-syncthing-relay-node.service

if [[ $? -eq 0 ]]; then
  systemctl --user stop container-syncthing-relay-node
  systemctl --user disable container-syncthing-relay-node
fi

podman container exists syncthing-relay-node

if [[ $? -eq 0 ]]; then
  podman stop syncthing-relay-node
  podman rm -f syncthing-relay-node
fi

if [[ "x$SYNCTHING_UPDATE" != "x" ]] || [[ "x$ROUTER_IMAGE_UPDATE" != "x" ]]; then
  podman image prune -a -f --filter "until=240h"
fi

if [[ -e "$SYNCTHING_SSL_CERT" ]] && [[ -e "$SYNCTHING_SSL_KEY" ]]; then
  SYNCTHING_RELAYSVR_EXT_OPTIONS=(-keys=/syncthing/ssl)
else
  SYNCTHING_RELAYSVR_EXT_OPTIONS=()
fi

if [[ ! -z "$SYNCTHING_RELAY_SERVER_EXT_ADDRSS" ]]; then
  SYNCTHING_RELAYSVR_EXT_OPTIONS=(${SYNCTHING_RELAYSVR_EXT_OPTIONS[@]} -ext-address "$SYNCTHING_RELAY_SERVER_EXT_ADDRSS")
fi

if [[ ! -z "$SYNCTHING_RELAY_POOL_ADDRESS" ]]; then
  SYNCTHING_RELAYSVR_EXT_OPTIONS=(${SYNCTHING_RELAYSVR_EXT_OPTIONS[@]} -pools "$SYNCTHING_RELAY_POOL_ADDRESS/endpoint")
else
  SYNCTHING_RELAYSVR_EXT_OPTIONS=(${SYNCTHING_RELAYSVR_EXT_OPTIONS[@]} -pools "")
fi

# --network=host \
#   -p $SYNCTHING_RELAY_SERVER_LISTEN_PORT:$SYNCTHING_RELAY_SERVER_LISTEN_PORT/tcp \
#   -p $SYNCTHING_RELAY_SERVER_LISTEN_PORT:$SYNCTHING_RELAY_SERVER_LISTEN_PORT/udp \
#   -p $SYNCTHING_RELAY_SERVER_STATUS_PORT:$SYNCTHING_RELAY_SERVER_STATUS_PORT/tcp \

podman run -d --name syncthing-relay-node --security-opt label=disable \
  --mount type=bind,source=$SYNCTHING_SSL_DIR,target=/syncthing/ssl/ \
  --mount type=bind,source=$SYNCTHING_DATA_DIR,target=/syncthing/data/ \
  --network=host \
  docker.io/syncthing/relaysrv:latest \
  ${SYNCTHING_RELAYSVR_EXT_OPTIONS[@]} \
  -listen ":$SYNCTHING_RELAY_SERVER_LISTEN_PORT" \
  -status-srv "127.0.0.1:$SYNCTHING_RELAY_SERVER_STATUS_PORT" \
  -protocol "tcp" \
  -provided-by "owent"

podman exec syncthing-relay-node ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime

podman generate systemd --name syncthing-relay-node | tee $SYNCTHING_ETC_DIR/container-syncthing-relay-node.service

podman stop syncthing-relay-node

systemctl --user enable $SYNCTHING_ETC_DIR/container-syncthing-relay-node.service
systemctl --user restart container-syncthing-relay-node
