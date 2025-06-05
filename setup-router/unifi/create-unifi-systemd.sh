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

if [[ "x$UNIFI_CONTROLLER_WEB_PORT" == "x" ]]; then
  UNIFI_CONTROLLER_WEB_PORT=6543
fi

if [[ "x$UNIFI_CONTROLLER_ROOT_DIR" == "x" ]]; then
  UNIFI_CONTROLLER_ROOT_DIR="$RUN_HOME/unifi"
fi
mkdir -p "$UNIFI_CONTROLLER_ROOT_DIR"

if [[ "x$UNIFI_CONTROLLER_ETC_DIR" == "x" ]]; then
  UNIFI_CONTROLLER_ETC_DIR="$UNIFI_CONTROLLER_ROOT_DIR/etc"
fi
mkdir -p "$UNIFI_CONTROLLER_ETC_DIR"

UNIFI_CONTROLLER_IMAGE="lscr.io/linuxserver/unifi-network-application"
# UNIFI_CONTROLLER_IMAGE="docker.io/linuxserver/unifi-network-application:latest"

if [[ "x$UNIFI_CONTROLLER_UPDATE" != "x" ]] || [[ "x$UNIFI_UPDATE" != "x" ]] || [[ "x$ROUTER_IMAGE_UPDATE" != "x" ]]; then
  podman pull $UNIFI_CONTROLLER_IMAGE
  if [[ $? -ne 0 ]]; then
    exit 1
  fi
fi

systemctl --user --all | grep -F container-unifi.service

if [[ $? -eq 0 ]]; then
  systemctl --user stop container-unifi
  systemctl --user disable container-unifi
fi

podman container exists unifi >/dev/null 2>&1

if [[ $? -eq 0 ]]; then
  podman stop unifi
  podman rm -f unifi
fi

if [[ "x$REDIS_UPDATE" != "x" ]] || [[ "x$ROUTER_IMAGE_UPDATE" != "x" ]]; then
  podman image prune -a -f --filter "until=240h"
fi

UNIFI_CONTROLLER_PORTS=(
  -p 3478:3478/udp   # Unifi STUN port
  -p 10001:10001/udp # Required for AP discovery
  -p 8080:8080       # Required for device communication
  -p 1900:1900/udp   # optional, Required for Make controller discoverable on L2 network option
  # -p 8843:8843     # optional, Unifi guest portal HTTPS redirect port
  # -p 8880:8880     # optional, Unifi guest portal HTTP redirect port
  # -p 6789:6789     # optional, For mobile throughput test
  # -p 5514:5514/udp # optional, Remote syslog port
)

podman run -d --name unifi --security-opt label=disable \
  -e PUID=1000 -e PGID=1000 -e "TZ=Asia/Shanghai" \
  -e MEM_LIMIT=1024 -e MEM_STARTUP=1024 \
  --mount type=bind,source=$UNIFI_CONTROLLER_ETC_DIR,target=/config \
  -p $UNIFI_CONTROLLER_WEB_PORT:8443 \
  ${UNIFI_CONTROLLER_PORTS[@]} \
  $UNIFI_CONTROLLER_IMAGE

podman stop unifi

podman generate systemd --name unifi | tee $UNIFI_CONTROLLER_ROOT_DIR/container-unifi.service

systemctl --user enable $UNIFI_CONTROLLER_ROOT_DIR/container-unifi.service
systemctl --user restart container-unifi
