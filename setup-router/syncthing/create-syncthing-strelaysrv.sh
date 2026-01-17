#!/bin/bash

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"

if [[ -e "$(dirname "$SCRIPT_DIR")/configure-router.sh" ]]; then
  source "$(dirname "$SCRIPT_DIR")/configure-router.sh"
elif [[ -e "$SCRIPT_DIR/configure-server.sh" ]]; then
  source "$SCRIPT_DIR/configure-server.sh"
fi

export XDG_RUNTIME_DIR="/run/user/$UID"
export DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR}/bus"

# SYNCTHING_NETWORK=(internal-frontend)
# SYNCTHING_PUBLISH=()

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

if [[ "x$SYNCTHING_RELAYSRV_ETC_DIR" == "x" ]]; then
  SYNCTHING_RELAYSRV_ETC_DIR="$RUN_HOME/syncthing/strelaysrv/etc"
fi
mkdir -p "$SYNCTHING_RELAYSRV_ETC_DIR"
chmod 777 "$SYNCTHING_RELAYSRV_ETC_DIR"

if [[ "x$SYNCTHING_DATA_DIR" == "x" ]]; then
  SYNCTHING_DATA_DIR="$RUN_HOME/syncthing/data"
fi
mkdir -p "$SYNCTHING_DATA_DIR"
chmod 777 "$SYNCTHING_DATA_DIR"

if [[ -e "$RUN_HOME/syncthing/strelaysrv.token.txt" ]]; then
  SYNCTHING_RELAYSRV_TOKEN=$(cat "$RUN_HOME/syncthing/strelaysrv.token.txt" | tr -d '\n\r ')
  echo "Found existing relay server token."
fi
if [[ -z "$SYNCTHING_RELAYSRV_TOKEN" ]]; then
  SYNCTHING_RELAYSRV_TOKEN=$(head -c 16 /dev/urandom | base64 | tr '/+' '_-' | tr -d '= \n\r')
  echo -n "$SYNCTHING_RELAYSRV_TOKEN" > "$RUN_HOME/syncthing/strelaysrv.token.txt"
  echo "Generated new relay server token."
fi

if [[ "x$SYNCTHING_UPDATE" != "x" ]] && [[ "x$ROUTER_IMAGE_UPDATE" != "x" ]]; then
  podman pull docker.io/syncthing/relaysrv:latest
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

SYNCTHING_RELAYSVR_EXT_OPTIONS=(
  -keys=/etc/strelaysrv
  -token "$SYNCTHING_RELAYSRV_TOKEN"
  -listen ":$SYNCTHING_RELAY_SERVER_LISTEN_PORT"
  -status-srv "127.0.0.1:$SYNCTHING_RELAY_SERVER_STATUS_PORT"
  -protocol "tcp"
  -provided-by "owent"
)

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

SYNCTHING_OPTIONS=(
  --mount type=bind,source=$SYNCTHING_DATA_DIR,target=/syncthing/data/
  --mount type=bind,source=$SYNCTHING_RELAYSRV_ETC_DIR,target=/etc/strelaysrv/
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
      -p "$SYNCTHING_RELAY_SERVER_LISTEN_PORT:$SYNCTHING_RELAY_SERVER_LISTEN_PORT/tcp"
      -p "$SYNCTHING_RELAY_SERVER_LISTEN_PORT:$SYNCTHING_RELAY_SERVER_LISTEN_PORT/udp"
      -p "$SYNCTHING_RELAY_SERVER_STATUS_PORT:$SYNCTHING_RELAY_SERVER_STATUS_PORT"
    )
  fi
else
  SYNCTHING_OPTIONS+=(--network=host)
fi

podman run -d --name syncthing-relay-node --security-opt label=disable \
  "${SYNCTHING_OPTIONS[@]}" \
  docker.io/syncthing/relaysrv:latest \
  "${SYNCTHING_RELAYSVR_EXT_OPTIONS[@]}"

if [[ $? -ne 0 ]]; then
  echo "Failed to start syncthing relay server container."
  exit 1
fi

if [[ "x$SYNCTHING_UPDATE" != "x" ]] || [[ "x$ROUTER_IMAGE_UPDATE" != "x" ]]; then
  podman image prune -a -f --filter "until=240h"
fi

podman exec syncthing-relay-node ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime

podman generate systemd --name syncthing-relay-node | tee $SYNCTHING_ETC_DIR/container-syncthing-relay-node.service

podman stop syncthing-relay-node

systemctl --user enable $SYNCTHING_ETC_DIR/container-syncthing-relay-node.service
systemctl --user restart container-syncthing-relay-node
