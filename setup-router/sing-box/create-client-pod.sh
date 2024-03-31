#!/bin/bash

# $ROUTER_HOME/sing-box/create-client-pod.sh

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
source "$(dirname "$SCRIPT_DIR")/configure-router.sh"

mkdir -p "$ROUTER_LOG_ROOT_DIR/vbox"

if [[ -z "$VBOX_ETC_DIR" ]]; then
  VBOX_ETC_DIR="$HOME/vbox/etc"
fi
if [[ -z "$VBOX_DATA_DIR" ]]; then
  VBOX_DATA_DIR="$HOME/vbox/data"
fi

mkdir -p "$VBOX_ETC_DIR"
mkdir -p "$VBOX_DATA_DIR"

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
  --mount type=bind,source=$VBOX_ETC_DIR,target=/etc/vbox/,ro=true \
  --mount type=bind,source=$VBOX_DATA_DIR,target=/var/lib/vbox \
  --mount type=bind,source=$ROUTER_LOG_ROOT_DIR/vbox,target=/var/log/vbox \
  --mount type=bind,source=$ACMESH_SSL_DIR,target=/data/ssl,ro=true \
  docker.io/owt5008137/vbox:latest -D /var/lib/vbox -C /etc/vbox/ run

# podman cp vbox-client:/usr/local/vbox-client/share/geo-all.tar.gz geo-all.tar.gz
# if [[ $? -eq 0 ]]; then
#   tar -axvf geo-all.tar.gz
#   if [ $? -eq 0 ]; then
#     bash "$SCRIPT_DIR/setup-geoip-geosite.sh"
#   fi
# fi

podman generate systemd vbox-client | tee /lib/systemd/system/vbox-client.service

podman container stop vbox-client

systemctl daemon-reload

# patch end
systemctl enable vbox-client
systemctl start vbox-client
