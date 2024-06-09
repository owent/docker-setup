#!/bin/bash

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
source "$(dirname "$SCRIPT_DIR")/configure-router.sh"

if [[ -z "$VBOX_ETC_DIR" ]]; then
  VBOX_ETC_DIR="$HOME/vbox/etc"
fi
if [[ -z "$VBOX_DATA_DIR" ]]; then
  VBOX_DATA_DIR="$HOME/vbox/data"
fi
if [[ -z "$VBOX_LOG_DIR" ]]; then
  if [[ ! -z "$ROUTER_LOG_ROOT_DIR" ]]; then
    VBOX_LOG_DIR="$ROUTER_LOG_ROOT_DIR/vbox"
  else
    VBOX_LOG_DIR="$HOME/vbox/data"
  fi
fi

mkdir -p "$VBOX_ETC_DIR"
mkdir -p "$VBOX_DATA_DIR"
mkdir -p "$VBOX_LOG_DIR"

if [[ "x$VBOX_UPDATE" != "x" ]] || [[ "x$ROUTER_IMAGE_UPDATE" != "x" ]]; then
  podman pull docker.io/owt5008137/vbox:latest
  if [[ $? -ne 0 ]]; then
    exit 1
  fi
fi

systemctl disable vbox-client || true
systemctl stop vbox-client || true

podman container inspect vbox-client >/dev/null 2>&1
if [[ $? -eq 0 ]]; then
  podman stop vbox-client
  podman rm -f vbox-client
fi

if [[ "x$VBOX_UPDATE" != "x" ]] || [[ "x$ROUTER_IMAGE_UPDATE" != "x" ]]; then
  podman image prune -a -f --filter "until=240h"
fi

podman run -d --name vbox-client --cap-add=NET_ADMIN --cap-add=NET_BIND_SERVICE \
  --network=host --security-opt label=disable \
  --device /dev/net/tun:/dev/net/tun \
  --mount type=bind,source=$VBOX_ETC_DIR,target=/etc/vbox/,ro=true \
  --mount type=bind,source=$VBOX_DATA_DIR,target=/var/lib/vbox \
  --mount type=bind,source=$VBOX_LOG_DIR,target=/var/log/vbox \
  --mount type=bind,source=$ACMESH_SSL_DIR,target=/data/ssl,ro=true \
  docker.io/owt5008137/vbox:latest -D /var/lib/vbox -C /etc/vbox/ run

if [[ $? -ne 0 ]]; then
  exit 1
fi

bash "$SCRIPT_DIR/setup-client-pod-ip-rules.sh"

if [[ $? -ne 0 ]]; then
  exit 1
fi

# Start systemd service

podman generate systemd vbox-client \
  | sed "/PIDFile=/a ExecStopPost=/bin/bash $SCRIPT_DIR/setup-client-pod-ip-rules.sh clear" \
  | sed "/PIDFile=/a ExecStartPost=/bin/bash $SCRIPT_DIR/setup-client-pod-ip-rules.sh" \
  | tee /lib/systemd/system/vbox-client.service

podman container stop vbox-client

systemctl daemon-reload

# patch end
systemctl enable vbox-client
systemctl start vbox-client
