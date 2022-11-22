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

if [[ "x$SYNCTHING_DISCOVERY_LISTEN_PORT" == "x" ]]; then
  SYNCTHING_DISCOVERY_LISTEN_PORT=6341
fi

if [[ "x$SYNCTHING_ETC_DIR" == "x" ]]; then
  SYNCTHING_ETC_DIR="$RUN_HOME/syncthing/etc"
fi
mkdir -p "$SYNCTHING_ETC_DIR"
chmod 777 "$SYNCTHING_ETC_DIR"

if [[ "x$SYNCTHING_DISCOVERY_DATA_DIR" == "x" ]]; then
  SYNCTHING_DISCOVERY_DATA_DIR="$RUN_HOME/syncthing/data"
fi
mkdir -p "$SYNCTHING_DISCOVERY_DATA_DIR"
chmod 777 "$SYNCTHING_DISCOVERY_DATA_DIR"

if [[ -z "$SYNCTHING_DISCOVERY_SSL_DIR" ]]; then
  SYNCTHING_DISCOVERY_SSL_DIR="$RUN_HOME/syncthing/ssl/"
fi
if [[ ! -e "$SYNCTHING_DISCOVERY_SSL_DIR" ]]; then
  mkdir -p "$SYNCTHING_DISCOVERY_SSL_DIR"
  chmod 777 "$SYNCTHING_DISCOVERY_SSL_DIR"
fi
SYNCTHING_DISCOVERY_SSL_COPY_TO_DIR="$RUN_HOME/syncthing/ssl/"
mkdir -p "$SYNCTHING_DISCOVERY_SSL_COPY_TO_DIR"
chmod 777 "$SYNCTHING_DISCOVERY_SSL_COPY_TO_DIR"

if [[ -z "$SYNCTHING_DISCOVERY_SSL_CERT" ]]; then
  SYNCTHING_DISCOVERY_SSL_CERT="cert.pem"
fi

if [[ -z "$SYNCTHING_DISCOVERY_SSL_KEY" ]]; then
  SYNCTHING_DISCOVERY_SSL_KEY="key.pem"
fi
systemctl --user --all | grep -F container-syncthing-discovery.service

if [[ $? -eq 0 ]]; then
  systemctl --user stop container-syncthing-discovery
  systemctl --user disable container-syncthing-discovery
fi

podman container inspect syncthing-discovery >/dev/null 2>&1

if [[ $? -eq 0 ]]; then
  podman stop syncthing-discovery
  podman rm -f syncthing-discovery
fi

if [[ "x$SYNCTHING_UPDATE" != "x" ]]; then
  podman image inspect docker.io/syncthing/discosrv:latest >/dev/null 2>&1
  if [[ $? -eq 0 ]]; then
    podman image rm -f docker.io/syncthing/discosrv:latest
  fi
fi

podman pull docker.io/syncthing/discosrv:latest

# Use these options if the discovery is not under a reserve proxy and remove -http
#   -cert=/syncthing/ssl/http-cert.pem \
#   -key=/syncthing/ssl/http-key.pem \
if [[ -e "$SYNCTHING_DISCOVERY_SSL_DIR/$SYNCTHING_DISCOVERY_SSL_CERT" ]] && [[ -e "$SYNCTHING_DISCOVERY_SSL_DIR/$SYNCTHING_DISCOVERY_SSL_KEY" ]]; then
  if [[ "$SYNCTHING_DISCOVERY_SSL_DIR" != "$SYNCTHING_DISCOVERY_SSL_COPY_TO_DIR" ]]; then
    cp -f "$SYNCTHING_DISCOVERY_SSL_DIR/$SYNCTHING_DISCOVERY_SSL_CERT" "$SYNCTHING_DISCOVERY_SSL_COPY_TO_DIR/$SYNCTHING_DISCOVERY_SSL_CERT"
    cp -f "$SYNCTHING_DISCOVERY_SSL_DIR/$SYNCTHING_DISCOVERY_SSL_KEY" "$SYNCTHING_DISCOVERY_SSL_COPY_TO_DIR/$SYNCTHING_DISCOVERY_SSL_KEY"
  fi
  chmod 666 "$SYNCTHING_DISCOVERY_SSL_COPY_TO_DIR/$SYNCTHING_DISCOVERY_SSL_CERT"
  chmod 666 "$SYNCTHING_DISCOVERY_SSL_COPY_TO_DIR/$SYNCTHING_DISCOVERY_SSL_KEY"
  SYNCTHING_SSL_OPTIONS=(-cert "/syncthing/ssl/$SYNCTHING_DISCOVERY_SSL_CERT" -key "/syncthing/ssl/$SYNCTHING_DISCOVERY_SSL_KEY" -http)
else
  SYNCTHING_SSL_OPTIONS=(-http)
fi
podman run -d --name syncthing-discovery --security-opt label=disable \
  --mount type=bind,source=$SYNCTHING_DISCOVERY_SSL_COPY_TO_DIR,target=/syncthing/ssl/ \
  --mount type=bind,source=$SYNCTHING_DISCOVERY_DATA_DIR,target=/syncthing/data/ \
  -p $SYNCTHING_DISCOVERY_LISTEN_PORT:$SYNCTHING_DISCOVERY_LISTEN_PORT/tcp \
  docker.io/syncthing/discosrv:latest \
  ${SYNCTHING_SSL_OPTIONS[@]} \
  -listen ":$SYNCTHING_DISCOVERY_LISTEN_PORT" \
  -db-dir /syncthing/data

podman exec syncthing-discovery ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime

podman generate systemd --name syncthing-discovery | tee $SYNCTHING_ETC_DIR/container-syncthing-discovery.service

podman stop syncthing-discovery

systemctl --user enable $SYNCTHING_ETC_DIR/container-syncthing-discovery.service
systemctl --user restart container-syncthing-discovery
