#!/bin/bash

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
source "$(dirname "$SCRIPT_DIR")/configure-router.sh"

export XDG_RUNTIME_DIR="/run/user/$UID"
export DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR}/bus"

DOCKER_EXEC=$((which podman > /dev/null 2>&1 && echo podman) || (which docker > /dev/null 2>&1 && echo docker))
DOCKER_EXEC_PATH="$(which $DOCKER_EXEC)"

if [[ "x$RUN_USER" == "x" ]]; then
  RUN_USER=$(id -un)
fi
RUN_HOME=$(cat /etc/passwd | awk "BEGIN{FS=\":\"} \$1 == \"$RUN_USER\" { print \$6 }")

if [[ "x$RUN_HOME" == "x" ]]; then
  RUN_HOME="$HOME"
fi

# 非 --network=host 下会导致丢失DNS请求来源信息
# UNBOUND_NETWORK=(host)
UNBOUND_RUN_USER=(root)
if [[ -z "$UNBOUND_ETC_DIR" ]]; then
  UNBOUND_ETC_DIR="$SCRIPT_DIR/unbound-etc"
fi
mkdir -p "$UNBOUND_ETC_DIR"

if [[ -z "$UNBOUND_DATA_DIR" ]]; then
  UNBOUND_DATA_DIR="$SCRIPT_DIR/unbound-data"
fi
mkdir -p "$UNBOUND_DATA_DIR"

if [[ -z "$UNBOUND_SSL_DIR" ]]; then
  UNBOUND_SSL_DIR="$SCRIPT_DIR/ssl"
fi
mkdir -p "$UNBOUND_SSL_DIR"

if [[ -z "$UNBOUND_IMAGE" ]]; then
  UNBOUND_IMAGE="alpinelinux/unbound:latest"
fi
$DOCKER_EXEC image inspect $UNBOUND_IMAGE > /dev/null 2>&1
if [[ $? -ne 0 ]]; then
  UNBOUND_UPDATE=1
fi
if [[ "x$UNBOUND_UPDATE" != "x" ]] || [[ "x$ROUTER_IMAGE_UPDATE" != "x" ]]; then
  $DOCKER_EXEC pull $UNBOUND_IMAGE
  if [[ $? -ne 0 ]]; then
    echo "Error: Unable to pull $UNBOUND_IMAGE"
    exit 1
  fi
fi
if [[ -z "$UNBOUND_RESOLV_CONF" ]]; then
  if [[ -e "$UNBOUND_ETC_DIR/resolv.conf" ]]; then
    UNBOUND_RESOLV_CONF="$UNBOUND_ETC_DIR/resolv.conf"
  else
    UNBOUND_RESOLV_CONF="/etc/resolv.conf"
  fi
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

systemctl --user --all | grep -F unbound.service

if [[ $? -eq 0 ]]; then
  systemctl --user stop unbound
  systemctl --user disable unbound
fi

$DOCKER_EXEC container exists unbound >/dev/null 2>&1

if [[ $? -eq 0 ]]; then
  $DOCKER_EXEC stop unbound
  $DOCKER_EXEC rm -f unbound
fi

if [[ "x$REDIS_UPDATE" != "x" ]] || [[ "x$ROUTER_IMAGE_UPDATE" != "x" ]]; then
  $DOCKER_EXEC image prune -a -f --filter "until=240h"
fi

UNBOUND_OPTIONS=(
  -e "TZ=Asia/Shanghai"
  --mount "type=bind,source=$UNBOUND_DATA_DIR,target=/etc/unbound"
  --mount "type=bind,source=$UNBOUND_SSL_DIR,target=/opt/unbound/ssl"
  -v "$UNBOUND_ETC_DIR/unbound.conf:/etc/unbound/unbound.conf:ro"
  -v "$UNBOUND_RESOLV_CONF:/etc/resolv.conf:ro"
)
UNBOUND_HAS_HOST_NETWORK=0
if [[ ! -z "$UNBOUND_NETWORK" ]]; then
  for network in ${UNBOUND_NETWORK[@]}; do
    UNBOUND_OPTIONS+=("--network=$network")
    if [[ $network == "host" ]]; then
      UNBOUND_HAS_HOST_NETWORK=1
    fi
  done
fi
if [[ $UNBOUND_HAS_HOST_NETWORK -eq 0 ]]; then
  if [[ ! -z "$UNBOUND_PORT" ]]; then
    for bing_port in ${UNBOUND_PORT[@]}; do
      UNBOUND_OPTIONS+=(-p "$bing_port")
    done
  fi
fi

if [[ ! -z "$UNBOUND_RUN_USER" ]]; then
  UNBOUND_OPTIONS+=("--user=$UNBOUND_RUN_USER")
fi

PODLET_IMAGE_URL="ghcr.io/containers/podlet:latest"
PODLET_RUN=($(which podlet 2>/dev/null))
FIND_PODLET_RESULT=$?
if [[ $FIND_PODLET_RESULT -ne 0 ]]; then
  (podman image inspect "$PODLET_IMAGE_URL" > /dev/null 2>&1 || podman pull "$PODLET_IMAGE_URL") && FIND_PODLET_RESULT=0 && PODLET_RUN=(podman run --rm "$PODLET_IMAGE_URL")
fi

if [[ $FIND_PODLET_RESULT -eq 0 ]]; then
  PODLET_OPTIONS=(--install --wanted-by default.target --wants network-online.target --after network-online.target)
  for network in ${UNBOUND_NETWORK[@]}; do
    if [[ -e "$HOME/.config/containers/systemd/$network.network" ]]; then
      PODLET_OPTIONS+=(--after "$network-network.service" --wants "$network-network.service")
    fi
  done
  ${PODLET_RUN[@]} "${PODLET_OPTIONS[@]}" \
    $DOCKER_EXEC run -d --name unbound --security-opt label=disable \
      "${UNBOUND_OPTIONS[@]}" \
      $UNBOUND_IMAGE | tee -p "$SYSTEMD_CONTAINER_DIR/unbound.container"
else
  $DOCKER_EXEC run -d --name unbound --security-opt label=disable \
    "${UNBOUND_OPTIONS[@]}" \
    $UNBOUND_IMAGE
  podman generate systemd unbound | tee -p "$SYSTEMD_SERVICE_DIR/unbound.service"
  podman container stop unbound
fi

if [[ "$SYSTEMD_SERVICE_DIR" == "/lib/systemd/system" ]]; then
  systemctl daemon-reload
else
  systemctl --user daemon-reload
fi

if [[ "$SYSTEMD_SERVICE_DIR" == "/lib/systemd/system" ]]; then
  if [[ $FIND_PODLET_RESULT -ne 0 ]]; then
    systemctl enable unbound.service
  fi
  systemctl start unbound.service
else
  if [[ $FIND_PODLET_RESULT -ne 0 ]]; then
    systemctl --user enable unbound.service
  fi
  systemctl --user start unbound.service
fi

if [[ "x$UNBOUND_UPDATE" != "x" ]] || [[ "x$ROUTER_IMAGE_UPDATE" != "x" ]]; then
  podman image prune -a -f --filter "until=240h"
fi
