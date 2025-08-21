#!/bin/bash

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
if [[ -e "$(dirname "$SCRIPT_DIR")/configure-router.sh" ]]; then
  source "$(dirname "$SCRIPT_DIR")/configure-router.sh"
fi

export XDG_RUNTIME_DIR="/run/user/$UID"
export DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR}/bus"

if [[ "x$RUN_USER" == "x" ]]; then
  RUN_USER=$(id -un)
fi
RUN_HOME=$(cat /etc/passwd | awk "BEGIN{FS=\":\"} \$1 == \"$RUN_USER\" { print \$6 }")

if [[ "x$RUN_HOME" == "x" ]]; then
  RUN_HOME="$HOME"
fi
# HAPROXY_NETWORK=(host)
# HAPROXY_RUN_USER=root
if [[ -z "$HAPROXY_ETC_DIR" ]]; then
  HAPROXY_ETC_DIR="$SCRIPT_DIR/etc"
fi
mkdir -p "$HAPROXY_ETC_DIR"

if [[ -z "$HAPROXY_IMAGE" ]]; then
  HAPROXY_IMAGE="haproxy:alpine"
  # HAPROXY_IMAGE="haproxy:lts"
fi
if [[ "x$HAPROXY_UPDATE" != "x" ]] || [[ "x$ROUTER_IMAGE_UPDATE" != "x" ]]; then
  podman pull $HAPROXY_IMAGE
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

if [[ "x$HAPROXY_UPDATE" != "x" ]] || [[ "x$ROUTER_IMAGE_UPDATE" != "x" ]]; then
  podman image prune -a -f --filter "until=240h"
fi

HAPROXY_OPTIONS=(-e "TZ=Asia/Shanghai"
  --mount "type=bind,source=$HAPROXY_ETC_DIR,target=/etc/haproxy"
)
if [[ ! -z "$HAPROXY_SSL_DIR" ]]; then
  HAPROXY_OPTIONS+=(--mount "type=bind,source=$HAPROXY_SSL_DIR,target=/etc/haproxy/ssl")
fi
HAPROXY_HAS_HOST_NETWORK=0
if [[ ! -z "$HAPROXY_NETWORK" ]]; then
  for network in ${HAPROXY_NETWORK[@]}; do
    HAPROXY_OPTIONS+=("--network=$network")
    if [[ $network == "host" ]]; then
      HAPROXY_HAS_HOST_NETWORK=1
    fi
  done
fi
if [[ $HAPROXY_HAS_HOST_NETWORK -eq 0 ]]; then
  if [[ ! -z "$HAPROXY_PORT" ]]; then
    for bing_port in ${HAPROXY_PORT[@]}; do
      HAPROXY_OPTIONS+=(-p "$bing_port")
    done
  fi
fi

if [[ ! -z "$HAPROXY_RUN_USER" ]]; then
  HAPROXY_OPTIONS+=("--user=$HAPROXY_RUN_USER")
fi

podman run -d --name haproxy --security-opt label=disable \
  "${HAPROXY_OPTIONS[@]}" \
  $HAPROXY_IMAGE \
  haproxy -f /etc/haproxy/haproxy.cfg

if [[ $? -ne 0 ]]; then
  echo "Error: Unable to start haproxy container"
  exit 1
fi

podman stop haproxy

podman generate systemd --name haproxy | tee $HAPROXY_ETC_DIR/container-haproxy.service

systemctl --user enable $HAPROXY_ETC_DIR/container-haproxy.service
systemctl --user restart container-haproxy
