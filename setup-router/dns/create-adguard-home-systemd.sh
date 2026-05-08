#!/bin/bash

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
source "$(dirname "$SCRIPT_DIR")/configure-router.sh"

DOCKER_EXEC=$((which podman > /dev/null 2>&1 && echo podman) || (which docker > /dev/null 2>&1 && echo docker))
DOCKER_EXEC_PATH="$(which $DOCKER_EXEC)"

export XDG_RUNTIME_DIR="/run/user/$UID"
export DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR}/bus"

if [[ "x$RUN_USER" == "x" ]]; then
  RUN_USER=$(id -un)
fi
RUN_HOME=$(cat /etc/passwd | awk "BEGIN{FS=\":\"} \$1 == \"$RUN_USER\" { print \$6 }")

if [[ "x$RUN_HOME" == "x" ]]; then
  RUN_HOME="$HOME"
fi

if [[ -z "$ADGUARD_HOME_IMAGE" ]]; then
  ADGUARD_HOME_IMAGE="adguard/adguardhome:latest"
fi
if [[ -z "$ADGUARD_HOME_PODNAME" ]]; then
  ADGUARD_HOME_PODNAME="adguardhome"
fi

# 非 --network=host 下会导致丢失DNS请求来源信息
# ADGUARD_HOME_NETWORK=(host)
# ADGUARD_HOME_RUN_USER=(root)
if [[ -z "$ADGUARD_HOME_ETC_DIR" ]]; then
  ADGUARD_HOME_ETC_DIR="$SCRIPT_DIR/$ADGUARD_HOME_PODNAME-etc"
fi
mkdir -p "$ADGUARD_HOME_ETC_DIR"

if [[ -z "$ADGUARD_HOME_SSL_DIR" ]]; then
  ADGUARD_HOME_SSL_DIR="$SCRIPT_DIR/ssl"
fi
mkdir -p "$ADGUARD_HOME_SSL_DIR"

if [[ -z "$ADGUARD_HOME_DATA_DIR" ]]; then
  ADGUARD_HOME_DATA_DIR="$SCRIPT_DIR/$ADGUARD_HOME_PODNAME-data"
fi
mkdir -p "$ADGUARD_HOME_DATA_DIR"

$DOCKER_EXEC image inspect $ADGUARD_HOME_IMAGE > /dev/null 2>&1
if [[ $? -ne 0 ]]; then
  ADGUARD_HOME_UPDATE=1
fi
if [[ "x$ADGUARD_HOME_UPDATE" != "x" ]] || [[ "x$ROUTER_IMAGE_UPDATE" != "x" ]]; then
  $DOCKER_EXEC pull $ADGUARD_HOME_IMAGE
  if [[ $? -ne 0 ]]; then
    echo "Error: Unable to pull $ADGUARD_HOME_IMAGE"
    exit 1
  fi
fi
if [[ -z "$ADGUARD_HOME_RESOLV_CONF" ]]; then
  if [[ -e "$ADGUARD_HOME_ETC_DIR/resolv.conf" ]]; then
    ADGUARD_HOME_RESOLV_CONF="$ADGUARD_HOME_ETC_DIR/resolv.conf"
  else
    ADGUARD_HOME_RESOLV_CONF="/etc/resolv.conf"
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

systemctl --user --all | grep -F $ADGUARD_HOME_PODNAME.service

if [[ $? -eq 0 ]]; then
  systemctl --user stop $ADGUARD_HOME_PODNAME
  systemctl --user disable $ADGUARD_HOME_PODNAME
fi

$DOCKER_EXEC container exists $ADGUARD_HOME_PODNAME >/dev/null 2>&1

if [[ $? -eq 0 ]]; then
  $DOCKER_EXEC stop $ADGUARD_HOME_PODNAME
  $DOCKER_EXEC rm -f $ADGUARD_HOME_PODNAME
fi

if [[ "x$ADGUARD_HOME_UPDATE" != "x" ]] || [[ "x$ROUTER_IMAGE_UPDATE" != "x" ]]; then
  $DOCKER_EXEC image prune -a -f --filter "until=240h"
fi

ADGUARD_HOME_OPTIONS=(
  -e "TZ=Asia/Shanghai"
  --mount "type=bind,source=$ADGUARD_HOME_ETC_DIR,target=/opt/adguardhome/conf"
  --mount "type=bind,source=$ADGUARD_HOME_SSL_DIR,target=/opt/adguardhome/ssl"
  --mount "type=bind,source=$ADGUARD_HOME_DATA_DIR,target=/opt/adguardhome/work"
  -v "$ADGUARD_HOME_RESOLV_CONF:/etc/resolv.conf:ro"
)
ADGUARD_HOME_HAS_HOST_NETWORK=0
if [[ ! -z "$ADGUARD_HOME_NETWORK" ]]; then
  for network in ${ADGUARD_HOME_NETWORK[@]}; do
    ADGUARD_HOME_OPTIONS+=("--network=$network")
    if [[ $network == "host" ]]; then
      ADGUARD_HOME_HAS_HOST_NETWORK=1
    fi
  done
fi
if [[ $ADGUARD_HOME_HAS_HOST_NETWORK -eq 0 ]]; then
  if [[ ! -z "$ADGUARD_HOME_PORT" ]]; then
    for bing_port in ${ADGUARD_HOME_PORT[@]}; do
      ADGUARD_HOME_OPTIONS+=(-p "$bing_port")
    done
  fi
fi

if [[ ! -z "$ADGUARD_HOME_RUN_USER" ]]; then
  ADGUARD_HOME_OPTIONS+=("--user=$ADGUARD_HOME_RUN_USER")
fi

PODLET_IMAGE_URL="ghcr.io/containers/podlet:latest"
PODLET_RUN=($(which podlet 2>/dev/null))
FIND_PODLET_RESULT=$?
if [[ $FIND_PODLET_RESULT -ne 0 ]]; then
  (podman image inspect "$PODLET_IMAGE_URL" > /dev/null 2>&1 || podman pull "$PODLET_IMAGE_URL") && FIND_PODLET_RESULT=0 && PODLET_RUN=(podman run --rm "$PODLET_IMAGE_URL")
fi

if [[ $FIND_PODLET_RESULT -eq 0 ]]; then
  PODLET_OPTIONS=(--install --wanted-by default.target --wants network-online.target --after network-online.target)
  for network in ${ADGUARD_HOME_NETWORK[@]}; do
    if [[ -e "$HOME/.config/containers/systemd/$network.network" ]]; then
      PODLET_OPTIONS+=(--after "$network-network.service" --wants "$network-network.service")
    fi
  done
  ${PODLET_RUN[@]} "${PODLET_OPTIONS[@]}" \
    $DOCKER_EXEC run -d --name $ADGUARD_HOME_PODNAME --security-opt label=disable \
      "${ADGUARD_HOME_OPTIONS[@]}" \
      $ADGUARD_HOME_IMAGE | tee -p "$SYSTEMD_CONTAINER_DIR/$ADGUARD_HOME_PODNAME.container"
else
  $DOCKER_EXEC run -d --name $ADGUARD_HOME_PODNAME --security-opt label=disable \
    "${ADGUARD_HOME_OPTIONS[@]}" \
    $ADGUARD_HOME_IMAGE
  podman generate systemd $ADGUARD_HOME_PODNAME | tee -p "$SYSTEMD_SERVICE_DIR/$ADGUARD_HOME_PODNAME.service"
  podman container stop $ADGUARD_HOME_PODNAME
fi

if [[ "$SYSTEMD_SERVICE_DIR" == "/lib/systemd/system" ]]; then
  systemctl daemon-reload
else
  systemctl --user daemon-reload
fi

if [[ "$SYSTEMD_SERVICE_DIR" == "/lib/systemd/system" ]]; then
  if [[ $FIND_PODLET_RESULT -ne 0 ]]; then
    systemctl enable $ADGUARD_HOME_PODNAME.service
  fi
  systemctl start $ADGUARD_HOME_PODNAME.service
else
  if [[ $FIND_PODLET_RESULT -ne 0 ]]; then
    systemctl --user enable $ADGUARD_HOME_PODNAME.service
  fi
  systemctl --user start $ADGUARD_HOME_PODNAME.service
fi

if [[ "x$ADGUARD_HOME_UPDATE" != "x" ]] || [[ "x$ROUTER_IMAGE_UPDATE" != "x" ]]; then
  podman image prune -a -f --filter "until=240h"
fi
