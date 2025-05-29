#!/bin/bash

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
source "$(dirname "$SCRIPT_DIR")/configure-router.sh"

DOCKER_EXEC=$((which podman > /dev/null 2>&1 && echo podman) || (which docker > /dev/null 2>&1 && echo docker))

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
if [[ -z "$VBOX_IMAGE_URL" ]]; then
  VBOX_IMAGE_URL="ghcr.io/owent/vbox:latest"
fi

mkdir -p "$VBOX_ETC_DIR"
mkdir -p "$VBOX_DATA_DIR"
mkdir -p "$VBOX_LOG_DIR"

if [[ "x$VBOX_UPDATE" != "x" ]] || [[ "x$ROUTER_IMAGE_UPDATE" != "x" ]]; then
  $DOCKER_EXEC pull "$VBOX_IMAGE_URL"
  if [[ $? -ne 0 ]]; then
    exit 1
  fi
fi

systemctl disable vbox-client || true
systemctl stop vbox-client || true

$DOCKER_EXEC container inspect vbox-client >/dev/null 2>&1
if [[ $? -eq 0 ]]; then
  $DOCKER_EXEC stop vbox-client
  $DOCKER_EXEC rm -f vbox-client
fi

if [[ "x$VBOX_UPDATE" != "x" ]] || [[ "x$ROUTER_IMAGE_UPDATE" != "x" ]]; then
  $DOCKER_EXEC image prune -a -f --filter "until=240h"
fi

$DOCKER_EXEC run -d --name vbox-client --cap-add=NET_ADMIN --cap-add=NET_BIND_SERVICE \
  --network=host --security-opt label=disable \
  --device /dev/net/tun:/dev/net/tun \
  --mount type=bind,source=$VBOX_ETC_DIR,target=/etc/vbox/,ro=true \
  --mount type=bind,source=$VBOX_DATA_DIR,target=/var/lib/vbox \
  --mount type=bind,source=$VBOX_LOG_DIR,target=/var/log/vbox \
  --mount type=bind,source=$ACMESH_SSL_DIR,target=/data/ssl,ro=true \
  "$VBOX_IMAGE_URL" -D /var/lib/vbox -C /etc/vbox/ run

if [[ $? -ne 0 ]]; then
  exit 1
fi

if [[ -z "$ROUTER_NET_LOCAL_ENABLE_VBOX" ]] || [[ $ROUTER_NET_LOCAL_ENABLE_VBOX -eq 0 ]]; then
  bash "$SCRIPT_DIR/setup-client-pod-ip-nft.sh" clear
  bash "$SCRIPT_DIR/setup-client-pod-ip-rules.sh"
else
  bash "$SCRIPT_DIR/setup-client-pod-ip-rules.sh" clear
  bash "$SCRIPT_DIR/setup-client-pod-ip-nft.sh"
fi

if [[ $? -ne 0 ]]; then
  exit 1
fi

# Start systemd service

if [[ -z "$ROUTER_NET_LOCAL_ENABLE_VBOX" ]] || [[ $ROUTER_NET_LOCAL_ENABLE_VBOX -eq 0 ]]; then
  $DOCKER_EXEC generate systemd vbox-client |
    sed "/PIDFile=/a ExecStopPost=/bin/bash $SCRIPT_DIR/setup-client-pod-whitelist-rules.sh clear" |
    sed "/PIDFile=/a ExecStartPost=/bin/bash $SCRIPT_DIR/setup-client-pod-whitelist-rules.sh" |
    tee /lib/systemd/system/vbox-client.service
else
  $DOCKER_EXEC generate systemd vbox-client |
    sed "/PIDFile=/a ExecStopPost=/bin/bash $SCRIPT_DIR/setup-client-pod-ip-nft.sh clear" |
    sed "/PIDFile=/a ExecStartPost=/bin/bash $SCRIPT_DIR/setup-client-pod-ip-nft.sh" |
    tee /lib/systemd/system/vbox-client.service
fi

$DOCKER_EXEC container stop vbox-client

systemctl daemon-reload

# patch end
systemctl enable vbox-client
systemctl start vbox-client
