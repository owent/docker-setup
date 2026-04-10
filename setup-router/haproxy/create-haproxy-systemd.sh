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

if [[ -z "$HAPROXY_DATA_DIR" ]]; then
  HAPROXY_DATA_DIR="$SCRIPT_DIR/data"
fi
mkdir -p "$HAPROXY_DATA_DIR/run"
mkdir -p "$HAPROXY_DATA_DIR/lib"
chmod 777 -R "$HAPROXY_DATA_DIR/run" "$HAPROXY_DATA_DIR/lib"

if [[ -z "$HAPROXY_IMAGE" ]]; then
  HAPROXY_IMAGE="haproxy:alpine"
  # HAPROXY_IMAGE="haproxy:lts"
fi
if [[ "x$HAPROXY_UPDATE" != "x" ]] || [[ "x$ROUTER_IMAGE_UPDATE" != "x" ]]; then
  podman pull $HAPROXY_IMAGE
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

systemctl --user --all | grep -F haproxy.service

if [[ $? -eq 0 ]]; then
  systemctl --user stop haproxy
  systemctl --user disable haproxy
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
  --mount "type=bind,source=$HAPROXY_DATA_DIR/run,target=/var/run/haproxy"
  --mount "type=bind,source=$HAPROXY_DATA_DIR/lib,target=/var/lib/haproxy"
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

PODLET_IMAGE_URL="ghcr.io/containers/podlet:latest"
PODLET_RUN=($(which podlet 2>/dev/null))
FIND_PODLET_RESULT=$?
if [[ $FIND_PODLET_RESULT -ne 0 ]]; then
  (podman image inspect "$PODLET_IMAGE_URL" > /dev/null 2>&1 || podman pull "$PODLET_IMAGE_URL") && FIND_PODLET_RESULT=0 && PODLET_RUN=(podman run --rm "$PODLET_IMAGE_URL")
fi

if [[ $FIND_PODLET_RESULT -eq 0 ]]; then
  PODLET_OPTIONS=(--install --wanted-by default.target --wants network-online.target --after network-online.target)
  for network in ${HAPROXY_NETWORK[@]}; do
    if [[ -e "$HOME/.config/containers/systemd/$network.network" ]]; then
      PODLET_OPTIONS+=(--after "$network-network.service" --wants "$network-network.service")
    fi
  done
  ${PODLET_RUN[@]} "${PODLET_OPTIONS[@]}" \
    podman run -d --name haproxy --security-opt label=disable \
      "${HAPROXY_OPTIONS[@]}" \
      $HAPROXY_IMAGE \
      haproxy -f /etc/haproxy/haproxy.cfg | tee -p "$SYSTEMD_CONTAINER_DIR/haproxy.container"
else
  podman run -d --name haproxy --security-opt label=disable \
        "${HAPROXY_OPTIONS[@]}" \
        $HAPROXY_IMAGE \
        haproxy -f /etc/haproxy/haproxy.cfg
  podman generate systemd haproxy | tee -p "$SYSTEMD_SERVICE_DIR/haproxy.service"
  podman container stop haproxy
fi

if [[ "$SYSTEMD_SERVICE_DIR" == "/lib/systemd/system" ]]; then
  systemctl daemon-reload
else
  systemctl --user daemon-reload
fi

if [[ "$SYSTEMD_SERVICE_DIR" == "/lib/systemd/system" ]]; then
  if [[ $FIND_PODLET_RESULT -ne 0 ]]; then
    systemctl enable haproxy.service
  fi
  systemctl start haproxy.service
else
  if [[ $FIND_PODLET_RESULT -ne 0 ]]; then
    systemctl --user enable haproxy.service
  fi
  systemctl --user start haproxy.service
fi

podman exec --user root haproxy /bin/sh -c 'chmod 777 -R /var/run/haproxy /var/lib/haproxy'

if [[ "x$HAPROXY_UPDATE" != "x" ]] || [[ "x$ROUTER_IMAGE_UPDATE" != "x" ]]; then
  podman image prune -a -f --filter "until=240h"
fi

