#!/bin/bash

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
source "$(dirname "$SCRIPT_DIR")/configure-router.sh"

export XDG_RUNTIME_DIR="/run/user/$UID"
export DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR}/bus"

if [[ "x$RUN_USER" == "x" ]]; then
  RUN_USER=$(id -un)
fi
RUN_HOME=$(cat /etc/passwd | awk "BEGIN{FS=\":\"} \$1 == \"$RUN_USER\" { print \$6 }")

if [[ "x$RUN_HOME" == "x" ]]; then
  RUN_HOME="$HOME"
fi

if [[ -z "$HAPROXY_ETC_DIR" ]]; then
  HAPROXY_ETC_DIR="$SCRIPT_DIR/etc"
fi
mkdir -p "$HAPROXY_ETC_DIR"

if [[ -z "$HAPROXY_IMAGE" ]]; then
  HAPROXY_IMAGE="haproxy:alpine"
fi
if [[ "x$HAPROXY_UPDATE" != "x" ]] || [[ "x$ROUTER_IMAGE_UPDATE" != "x" ]]; then
  podman pull $HAPROXY_ZERO_TRUST_TUNNEL_IMAGE
fi

systemctl --user --all | grep -F container-haproxy.service

if [[ $? -eq 0 ]]; then
  systemctl --user stop container-haproxy
  systemctl --user disable container-haproxy
fi

podman container exists haproxy >/dev/null 2>&1

if [[ $? -eq 0 ]]; then
  podman stop haproxy
  podman rm -f haproxy
fi

if [[ "x$REDIS_UPDATE" != "x" ]] || [[ "x$ROUTER_IMAGE_UPDATE" != "x" ]]; then
  podman image prune -a -f --filter "until=240h"
fi

podman run -d --name haproxy --security-opt label=disable \
  -e "TZ=Asia/Shanghai" \
  --mount "type=bind,source=$PWD/etc,target=/etc/haproxy" \
  $HAPROXY_IMAGE \
  haproxy -c -f /etc/haproxy/haproxy.cfg

podman stop haproxy

podman generate systemd --name haproxy | tee $HAPROXY_ETC_DIR/container-haproxy.service

systemctl --user enable $HAPROXY_ETC_DIR/container-haproxy.service
systemctl --user restart container-haproxy
