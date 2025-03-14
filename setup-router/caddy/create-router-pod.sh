#!/bin/bash

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
source "$(dirname "$SCRIPT_DIR")/configure-router.sh"

# Require net.ipv4.ip_unprivileged_port_start=80 in /etc/sysctl.d/*.conf
# See https://github.com/containers/podman/blob/master/rootless.md

if [[ "x$CADDY_UPDATE" != "x" ]] || [[ "x$ROUTER_IMAGE_UPDATE" != "x" ]]; then
  podman pull docker.io/caddy:builder
  podman pull docker.io/caddy:latest
  if [[ $? -ne 0 ]]; then
    echo "Pull docker.io/caddy:builder and docker.io/caddy:latest failed"
    exit 1
  fi
fi

if [[ ! -e "Caddyfile" ]]; then
  cp -f sample.Caddyfile Caddyfile
fi

podman build --env GOPROXY=https://mirrors.cloud.tencent.com/go/,https://goproxy.io,direct --layers --force-rm --tag local-caddy -f build.Dockerfile .

if [[ $? -ne 0 ]]; then
  exit 1
fi

if [[ $? -ne 0 ]]; then
  exit 1
fi

if [[ "root" == "$(id -un)" ]]; then
  SYSTEMD_SERVICE_DIR=/lib/systemd/system
else
  SYSTEMD_SERVICE_DIR="$HOME/.config/systemd/user"
  mkdir -p "$SYSTEMD_SERVICE_DIR"
fi

if [[ "$SYSTEMD_SERVICE_DIR" == "/lib/systemd/system" ]]; then
  systemctl --all | grep -F router-caddy.service >/dev/null 2>&1
  if [ $? -eq 0 ]; then
    systemctl stop router-caddy.service
    systemctl disable router-caddy.service
  fi
else
  export XDG_RUNTIME_DIR="/run/user/$UID"
  export DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR}/bus"

  # Maybe need run from host: loginctl enable-linger tools
  # see https://wiki.archlinux.org/index.php/Systemd/User
  # sudo loginctl enable-linger $RUN_USER
  systemctl --user --all | grep -F router-caddy.service >/dev/null 2>&1
  if [ $? -eq 0 ]; then
    systemctl --user stop router-caddy.service
    systemctl --user disable router-caddy.service
  fi
fi

podman container inspect router-caddy >/dev/null 2>&1

if [[ $? -eq 0 ]]; then
  podman stop router-caddy
  podman rm -f router-caddy
fi

if [[ "x$CADDY_UPDATE" != "x" ]] || [[ "x$ROUTER_IMAGE_UPDATE" != "x" ]]; then
  podman image prune -a -f --filter "until=240h"
fi

mkdir -p "$ROUTER_LOG_ROOT_DIR/caddy"
if [[ "x$ARIA2_DATA_ROOT" == "x" ]]; then
  if [[ ! -z "$SAMBA_DATA_DIR" ]]; then
    ARIA2_DATA_ROOT="$SAMBA_DATA_DIR/download"
  elif [[ ! -z "$ROUTER_DATA_ROOT_DIR" ]]; then
    ARIA2_DATA_ROOT="$ROUTER_DATA_ROOT_DIR/aria2/download"
  else
    ARIA2_DATA_ROOT="$HOME/aria2/download"
  fi
fi
mkdir -p "$ARIA2_DATA_ROOT"

CADDY_OPTIONS=(
  --mount type=bind,source=$ACMESH_SSL_DIR,target=/data/ssl,ro=true
  --mount type=bind,source=$ROUTER_LOG_ROOT_DIR/caddy,target=/var/log/caddy
  "--mount" "type=bind,source=$ARIA2_DATA_ROOT,target=/data/website/html/downloads"
)

if [[ "x$NEXTCLOUD_REVERSE_ROOT_DIR" != "x" ]]; then
  CADDY_OPTIONS+=(
    "--mount" "type=bind,source=$NEXTCLOUD_REVERSE_ROOT_DIR/nextcloud,target=/data/website/html/nextcloud"
    "--mount" "type=bind,source=$NEXTCLOUD_APPS_DIR,target=/data/website/html/nextcloud/custom_apps"
  )
fi

if [[ ! -z "$CADDY_NETWORK" ]]; then
  for network in ${CADDY_NETWORK[@]}; do
    CADDY_OPTIONS+=("--network=$network")
  done
  if [[ ! -z "$CADDY_PUBLISH" ]]; then
    for publish in ${CADDY_PUBLISH[@]}; do
      CADDY_OPTIONS+=(-p "$publish")
    done
  fi
else
  CADDY_OPTIONS+=(--network=host)
fi

unset http_proxy
unset https_proxy

podman run -d --name router-caddy --security-opt label=disable \
  ${CADDY_OPTIONS[@]} \
  local-caddy

podman generate systemd router-caddy | tee -p "$SYSTEMD_SERVICE_DIR/router-caddy.service"
podman container stop router-caddy

if [[ "$SYSTEMD_SERVICE_DIR" == "/lib/systemd/system" ]]; then
  systemctl enable router-caddy.service
  systemctl daemon-reload
  systemctl start router-caddy.service
else
  systemctl --user enable "$SYSTEMD_SERVICE_DIR/router-caddy.service"
  systemctl --user daemon-reload
  systemctl --user start router-caddy.service
fi
