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

if [[ "x$GEOIP_LICENSE_KEY" == "x" ]]; then
  GEOIP_LICENSE_KEY="<License Key from https://www.maxmind.com/>"
fi
if [[ "x$GEOIP_ACCOUNT_ID" == "x" ]]; then
  GEOIP_ACCOUNT_ID="<Account from https://www.maxmind.com/>"
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

if [[ "x$SYNCTHING_UPDATE" != "x" ]] && [[ "x$ROUTER_IMAGE_UPDATE" != "x" ]]; then
  podman image pull docker.io/syncthing/strelaypoolsrv:latest
  if [[ $? -ne 0 ]]; then
    exit 1
  fi
fi

systemctl --user --all | grep -F container-syncthing-relay-pool.service

if [[ $? -eq 0 ]]; then
  systemctl --user stop container-syncthing-relay-pool
  systemctl --user disable container-syncthing-relay-pool
fi

podman container exists syncthing-relay-pool

if [[ $? -eq 0 ]]; then
  podman stop syncthing-relay-pool
  podman rm -f syncthing-relay-pool
fi

if [[ "x$SYNCTHING_UPDATE" != "x" ]] || [[ "x$ROUTER_IMAGE_UPDATE" != "x" ]]; then
  podman image prune -a -f --filter "until=240h"
fi

if [[ -e "$SYNCTHING_SSL_CERT" ]] && [[ -e "$SYNCTHING_SSL_KEY" ]]; then
  SYNCTHING_RELAYPOOL_EXT_OPTIONS=(-keys /syncthing/ssl)
else
  SYNCTHING_RELAYPOOL_EXT_OPTIONS=()
fi

if [[ ! -z "$SYNCTHING_RELAY_POOL_IP_HEADER" ]]; then
  SYNCTHING_RELAYPOOL_EXT_OPTIONS=(${SYNCTHING_RELAYPOOL_EXT_OPTIONS[@]} "-ip-header" "$SYNCTHING_RELAY_POOL_IP_HEADER")
fi

podman run -d --name syncthing-relay-pool --security-opt label=disable \
  -e "GEOIP_LICENSE_KEY=$GEOIP_LICENSE_KEY" -e "GEOIP_ACCOUNT_ID=$GEOIP_ACCOUNT_ID" \
  --mount type=bind,source=$SYNCTHING_SSL_DIR,target=/syncthing/ssl/ \
  --mount type=bind,source=$SYNCTHING_DATA_DIR,target=/syncthing/data/ \
  -p 127.0.0.1:$SYNCTHING_RELAY_POOL_LISTEN_PORT:$SYNCTHING_RELAY_POOL_LISTEN_PORT/tcp \
  docker.io/syncthing/strelaypoolsrv:latest \
  ${SYNCTHING_RELAYPOOL_EXT_OPTIONS[@]} \
  -listen ":$SYNCTHING_RELAY_POOL_LISTEN_PORT" \
  -protocol "tcp"

podman exec syncthing-relay-pool ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime

podman generate systemd --name syncthing-relay-pool | tee $SYNCTHING_ETC_DIR/container-syncthing-relay-pool.service

podman stop syncthing-relay-pool

systemctl --user enable $SYNCTHING_ETC_DIR/container-syncthing-relay-pool.service
systemctl --user restart container-syncthing-relay-pool
