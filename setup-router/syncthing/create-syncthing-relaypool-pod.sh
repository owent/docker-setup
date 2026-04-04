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

if [[ "x$SYNCTHING_UPDATE" != "x" ]] && [[ "x$ROUTER_IMAGE_UPDATE" != "x" ]]; then
  podman image pull docker.io/syncthing/strelaypoolsrv:latest
  if [[ $? -ne 0 ]]; then
    exit 1
  fi
fi

systemctl --user --all | grep -F syncthing-relay-pool.service

if [[ $? -eq 0 ]]; then
  systemctl --user stop syncthing-relay-pool
  systemctl --user disable syncthing-relay-pool
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

PODLET_IMAGE_URL="ghcr.io/containers/podlet:latest"
PODLET_RUN=($(which podlet >/dev/null 2>&1))
FIND_PODLET_RESULT=$?
if [[ $FIND_PODLET_RESULT -ne 0 ]]; then
  podman image inspect "$PODLET_IMAGE_URL" > /dev/null 2>&1 && FIND_PODLET_RESULT=0 && PODLET_RUN=(podman run --rm "$PODLET_IMAGE_URL")
fi

if [[ $FIND_PODLET_RESULT -eq 0 ]]; then
  ${PODLET_RUN[@]} --install --wanted-by default.target --wants network-online.target --after network-online.target \
    podman run -d --name syncthing-relay-pool --security-opt label=disable \
      -e "GEOIP_LICENSE_KEY=$GEOIP_LICENSE_KEY" -e "GEOIP_ACCOUNT_ID=$GEOIP_ACCOUNT_ID" \
      --mount type=bind,source=$SYNCTHING_SSL_DIR,target=/syncthing/ssl/ \
      --mount type=bind,source=$SYNCTHING_DATA_DIR,target=/syncthing/data/ \
      -p 127.0.0.1:$SYNCTHING_RELAY_POOL_LISTEN_PORT:$SYNCTHING_RELAY_POOL_LISTEN_PORT/tcp \
      docker.io/syncthing/strelaypoolsrv:latest \
      ${SYNCTHING_RELAYPOOL_EXT_OPTIONS[@]} \
      -listen ":$SYNCTHING_RELAY_POOL_LISTEN_PORT" \
      -protocol "tcp" \
      | tee -p "$SYSTEMD_CONTAINER_DIR/syncthing-relay-pool.container"
  
  systemctl --user daemon-reload

else

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

  podman generate systemd --name syncthing-relay-pool | tee $SYSTEMD_SERVICE_DIR/syncthing-relay-pool.service

  podman stop syncthing-relay-pool

  systemctl --user daemon-reload
  systemctl --user enable syncthing-relay-pool
fi

systemctl --user restart syncthing-relay-pool

if [[ "x$SYNCTHING_UPDATE" != "x" ]] || [[ "x$ROUTER_IMAGE_UPDATE" != "x" ]]; then
  podman image prune -a -f --filter "until=240h"
fi
