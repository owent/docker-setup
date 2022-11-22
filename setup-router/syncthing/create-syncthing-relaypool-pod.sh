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

if [[ "x$SYNCTHING_RELAY_POOL_LISTEN_PORT" == "x" ]]; then
  SYNCTHING_RELAY_POOL_LISTEN_PORT=6345
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
  SYNCTHING_SSL_CERT="$SYNCTHING_SSL_DIR/http-cert.pem"
fi

if [[ "x$SYNCTHING_SSL_KEY" == "x" ]]; then
  SYNCTHING_SSL_KEY="$SYNCTHING_SSL_DIR/http-key.pem"
fi

systemctl --user --all | grep -F container-syncthing-relay-pool.service

if [[ $? -eq 0 ]]; then
  systemctl --user stop container-syncthing-relay-pool
  systemctl --user disable container-syncthing-relay-pool
fi

podman container inspect syncthing-relay-pool >/dev/null 2>&1

if [[ $? -eq 0 ]]; then
  podman stop syncthing-relay-pool
  podman rm -f syncthing-relay-pool
fi

if [[ "x$SYNCTHING_UPDATE" != "x" ]]; then
  podman image inspect docker.io/syncthing/strelaypoolsrv:latest >/dev/null 2>&1
  if [[ $? -eq 0 ]]; then
    podman image rm -f docker.io/syncthing/strelaypoolsrv:latest
  fi
fi

podman pull docker.io/syncthing/strelaypoolsrv:latest

if [[ -e "$SYNCTHING_SSL_CERT" ]] && [[ -e "$SYNCTHING_SSL_KEY" ]]; then
  SYNCTHING_SSL_OPTIONS=(-keys /syncthing/ssl)
else
  SYNCTHING_SSL_OPTIONS=()
fi

podman run -d --name syncthing-relay-pool --security-opt label=disable \
  --mount type=bind,source=$SYNCTHING_SSL_DIR,target=/syncthing/ssl/ \
  --mount type=bind,source=$SYNCTHING_DATA_DIR,target=/syncthing/data/ \
  -p $SYNCTHING_RELAY_POOL_LISTEN_PORT:$SYNCTHING_RELAY_POOL_LISTEN_PORT/tcp \
  docker.io/syncthing/strelaypoolsrv:latest \
  ${SYNCTHING_SSL_OPTIONS[@]} \
  -listen ":$SYNCTHING_RELAY_POOL_LISTEN_PORT" \
  -protocol "tcp"

podman exec syncthing-relay-pool ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime

podman generate systemd --name syncthing-relay-pool | tee $SYNCTHING_ETC_DIR/container-syncthing-relay-pool.service

podman stop syncthing-relay-pool

systemctl --user enable $SYNCTHING_ETC_DIR/container-syncthing-relay-pool.service
systemctl --user restart container-syncthing-relay-pool
