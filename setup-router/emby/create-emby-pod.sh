#!/bin/bash

# @see https://hub.docker.com/r/emby/embyserver
# @see https://hub.docker.com/r/linuxserver/emby
# https://github.com/MediaBrowser/Wiki/wiki
# Kodi Addon(repository): https://kodi.emby.tv/

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
source "$(dirname "$SCRIPT_DIR")/configure-router.sh"

if [[ "root" == "$(id -un)" ]]; then
  SYSTEMD_SERVICE_DIR=/lib/systemd/system
else
  SYSTEMD_SERVICE_DIR="$HOME/.config/systemd/user"
  mkdir -p "$SYSTEMD_SERVICE_DIR"
fi

if [[ -z "$EMBY_DOCKER_IMAGE" ]]; then
  EMBY_DOCKER_IMAGE="docker.io/linuxserver/emby:latest"
  # EMBY_DOCKER_IMAGE="lscr.io/linuxserver/emby:latest"
  # EMBY_DOCKER_IMAGE=docker.io/emby/embyserver:latest
fi

if [[ -z "$EMBY_CONFIG_DIR" ]]; then
  EMBY_CONFIG_DIR="$ROUTER_DATA_ROOT_DIR/emby/config"
fi
mkdir -p "$EMBY_CONFIG_DIR"
if [[ -z "$EMBY_DATA_MEDIA_DIR" ]]; then
  EMBY_DATA_MEDIA_DIR="$ROUTER_DATA_ROOT_DIR/emby/data/media"
fi
mkdir -p "$EMBY_DATA_MEDIA_DIR"
if [[ -z "$EMBY_DATA_CACHE_DIR" ]]; then
  EMBY_DATA_CACHE_DIR="$ROUTER_DATA_ROOT_DIR/emby/cache"
fi
mkdir -p "$EMBY_DATA_CACHE_DIR"

if [[ -z "$EMBY_DOCKER_HTTP_PORT" ]]; then
  EMBY_DOCKER_HTTP_PORT=8096
fi
if [[ -z "$EMBY_DOCKER_HTTPS_PORT" ]]; then
  EMBY_DOCKER_HTTPS_PORT=8920
fi

if [[ ${#EMBY_DATA_EXTERNAL_DIRS[@]} -eq 0 ]]; then
  EMBY_DATA_EXTERNAL_DIRS=()
  if [[ ! -z "$ARIA2_DATA_ROOT" ]] && [[ -e "$ARIA2_DATA_ROOT/download" ]]; then
    EMBY_DATA_EXTERNAL_DIRS=(${EMBY_DATA_EXTERNAL_DIRS[@]} "$ARIA2_DATA_ROOT/download:download")
  fi
fi

EMBY_DOCKER_OPTIONS=(
  # -e PUID=$(id -u) # The UID to run emby as (default: 2, also maybe UID)
  # -e PGID=$(id -g) # The GID to run emby as (default 2, also maybe GID)
  # --env GIDLIST=100 \ # A comma-separated list of additional GIDs to run emby as (default: 2)
  -e "TZ=Asia/Shanghai"
  -p $EMBY_DOCKER_HTTP_PORT:8096
  --mount "type=bind,source=$EMBY_CONFIG_DIR,target=/config"
  --mount "type=bind,source=$EMBY_DATA_MEDIA_DIR,target=/data/media"
)

if [[ $(id -u) -ne 0 ]]; then
  EMBY_DOCKER_OPTIONS=(${EMBY_DOCKER_OPTIONS[@]} -e PUID=0 -e PGID=0)
fi

if [[ ! -z "$EMBY_DOCKER_HTTPS_PORT" ]]; then
  EMBY_DOCKER_OPTIONS=(${EMBY_DOCKER_OPTIONS[@]} -p $EMBY_DOCKER_HTTPS_PORT:8920)
fi
for EMBY_DATA_EXTERNAL_DIR in ${EMBY_DATA_EXTERNAL_DIRS[@]}; do
  EMBY_DATA_EXTERNAL_DIR_FROM="${EMBY_DATA_EXTERNAL_DIR%%:*}"
  EMBY_DATA_EXTERNAL_DIR_TO="${EMBY_DATA_EXTERNAL_DIR//*:/}"
  if [[ -e "$EMBY_DATA_EXTERNAL_DIR_FROM" ]] && [[ ! -z "$EMBY_DATA_EXTERNAL_DIR_TO" ]]; then
    EMBY_DOCKER_OPTIONS=(${EMBY_DOCKER_OPTIONS[@]} --mount "type=bind,source=$EMBY_DATA_EXTERNAL_DIR_FROM,target=/data/external/$EMBY_DATA_EXTERNAL_DIR_TO")
  fi
done

# Intel Quicksync and AMD VAAPI
if [[ -e "/dev/dri" ]]; then
  EMBY_DOCKER_OPTIONS=(${EMBY_DOCKER_OPTIONS[@]} "--device=/dev/dri:/dev/dri")
fi

# nvidia
if [[ ! -z "$EMBY_DOCKER_ENABLE_NVIDIA_RUNTIME" ]] && [[ "x$EMBY_DOCKER_ENABLE_NVIDIA_RUNTIME" != "x0" ]] \
  && [[ "x$EMBY_DOCKER_ENABLE_NVIDIA_RUNTIME" != "xno" ]] && [[ "x$EMBY_DOCKER_ENABLE_NVIDIA_RUNTIME" != "xfalse" ]]; then
  # Install runtime: https://github.com/NVIDIA/nvidia-docker
  EMBY_DOCKER_OPTIONS=(${EMBY_DOCKER_OPTIONS[@]} "--runtime=nvidia" -e "NVIDIA_VISIBLE_DEVICES=all")
fi

# OpenMAX (Raspberry Pi)
if [[ -e "/dev/vchiq" ]]; then
  EMBY_DOCKER_OPTIONS=(${EMBY_DOCKER_OPTIONS[@]} "--device=/dev/vchiq:/dev/vchiq" -v "/opt/vc/lib:/opt/vc/lib")
fi

# V4L2 (Raspberry Pi)
if [[ -e "/dev/video10" ]]; then
  EMBY_DOCKER_OPTIONS=(${EMBY_DOCKER_OPTIONS[@]} "--device=/dev/video10:/dev/video10")
fi
if [[ -e "/dev/video11" ]]; then
  EMBY_DOCKER_OPTIONS=(${EMBY_DOCKER_OPTIONS[@]} "--device=/dev/video11:/dev/video11")
fi
if [[ -e "/dev/video12" ]]; then
  EMBY_DOCKER_OPTIONS=(${EMBY_DOCKER_OPTIONS[@]} "--device=/dev/video12:/dev/video12")
fi

if [[ "x$EMBY_UPDATE" != "x" ]] || [[ "x$ROUTER_IMAGE_UPDATE" != "x" ]]; then
  podman image pull $EMBY_DOCKER_IMAGE
fi

if [[ "$SYSTEMD_SERVICE_DIR" == "/lib/systemd/system" ]]; then
  systemctl --all | grep -F emby-server.service >/dev/null 2>&1
  if [ $? -eq 0 ]; then
    systemctl stop emby-server.service
    systemctl disable emby-server.service
  fi
else
  export XDG_RUNTIME_DIR="/run/user/$UID"
  export DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR}/bus"

  # Maybe need run from host: loginctl enable-linger tools
  # see https://wiki.archlinux.org/index.php/Systemd/User
  # sudo loginctl enable-linger $RUN_USER
  systemctl --user --all | grep -F emby-server.service >/dev/null 2>&1
  if [ $? -eq 0 ]; then
    systemctl --user stop emby-server.service
    systemctl --user disable emby-server.service
  fi
fi

podman container inspect emby-server >/dev/null 2>&1
if [[ $? -eq 0 ]]; then
  podman stop emby-server
  podman rm -f emby-server
fi

if [[ "x$EMBY_UPDATE" != "x" ]] || [[ "x$ROUTER_IMAGE_UPDATE" != "x" ]]; then
  podman image prune -a -f --filter "until=240h"
fi

# --network=host is required for DLNA and Wake-on-Lan
podman run --network=host --name emby-server -d \
  --security-opt label=disable \
  ${EMBY_DOCKER_OPTIONS[@]} \
  $EMBY_DOCKER_IMAGE

if [[ 0 -ne $? ]]; then
  exit $?
fi

podman generate systemd emby-server | tee "$SYSTEMD_SERVICE_DIR/emby-server.service"
podman stop emby-server

if [[ "$SYSTEMD_SERVICE_DIR" == "/lib/systemd/system" ]]; then
  systemctl daemon-reload
  systemctl enable emby-server.service
  systemctl start emby-server.service
else
  systemctl --user daemon-reload
  systemctl --user enable "$SYSTEMD_SERVICE_DIR/emby-server.service"
  systemctl --user start emby-server.service
fi
