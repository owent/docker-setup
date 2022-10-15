#!/bin/bash

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
source "$(dirname "$SCRIPT_DIR")/configure-router.sh"

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
  SYNCTHING_DISCOVERY_LISTEN_PORT=8341
fi
if [[ "x$SYNCTHING_DISCOVERY_LISTEN_REPLICATION_PORT" == "x" ]]; then
  SYNCTHING_DISCOVERY_LISTEN_REPLICATION_PORT=8351
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

if [[ "x$SYNCTHING_SSL_CERT" == "x" ]] && [[ -e "/home/website/ssl/fullchain.cer" ]]; then
  SYNCTHING_SSL_CERT="/home/website/ssl/fullchain.cer"
fi
if [[ "x$SYNCTHING_SSL_CERT" != "x" ]] && [[ -e "$SYNCTHING_SSL_CERT" ]]; then
  if [[ "x$SYNCTHING_UPDATE" != "x" ]] || [[ "x$SYNCTHING_UPDATE_SSL" != "x" ]] || [[ ! -e "$SYNCTHING_SSL_DIR/fullchain.cer" ]]; then
    cp -f "$SYNCTHING_SSL_CERT" "$SYNCTHING_SSL_DIR/fullchain.cer"
    chmod 666 "$SYNCTHING_SSL_DIR/fullchain.cer"
  fi
fi

if [[ "x$SYNCTHING_SSL_KEY" == "x" ]] && [[ -e "/home/website/ssl/owent.net.key" ]]; then
  SYNCTHING_SSL_KEY="/home/website/ssl/owent.net.key"
fi
if [[ "x$SYNCTHING_SSL_KEY" != "x" ]] && [[ -e "$SYNCTHING_SSL_KEY" ]]; then
  if [[ "x$SYNCTHING_UPDATE" != "x" ]] || [[ "x$SYNCTHING_UPDATE_SSL" != "x" ]] || [[ ! -e "$SYNCTHING_SSL_DIR/st-discovery.x-ha.com.key" ]]; then
    cp -f "$SYNCTHING_SSL_KEY" "$SYNCTHING_SSL_DIR/st-discovery.x-ha.com.key"
    chmod 666 "$SYNCTHING_SSL_DIR/st-discovery.x-ha.com.key"
  fi
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
#   -cert=/syncthing/ssl/fullchain.cer \
#   -key=/syncthing/ssl/st-discovery.x-ha.com.key \
podman run -d --name syncthing-discovery --security-opt label=disable \
  --mount type=bind,source=$SYNCTHING_SSL_DIR,target=/syncthing/ssl/ \
  --mount type=bind,source=$SYNCTHING_DATA_DIR,target=/syncthing/data/ \
  -p $SYNCTHING_DISCOVERY_LISTEN_PORT:8443/tcp \
  docker.io/syncthing/discosrv:latest \
  -cert=/syncthing/ssl/fullchain.cer \
  -key=/syncthing/ssl/st-discovery.x-ha.com.key \
  -http \
  -db-dir=/syncthing/data

podman exec syncthing-discovery ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime

podman generate systemd --name syncthing-discovery | tee $SYNCTHING_ETC_DIR/container-syncthing-discovery.service

systemctl --user enable $SYNCTHING_ETC_DIR/container-syncthing-discovery.service
systemctl --user restart container-syncthing-discovery
