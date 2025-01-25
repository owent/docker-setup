#!/bin/bash

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"

PODMAN_COMMON_OPTIONS=(--cgroup-manager=cgroupfs)

PROXY_CADDY_DNSPOD_TOKEN="" # ID,Token
PROXY_CADDY_CLOUDFLARE_API_TOKEN=""

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

podman build ${PODMAN_COMMON_OPTIONS[@]} --env GOPROXY=https://mirrors.cloud.tencent.com/go/,https://goproxy.io,direct --layers --force-rm --tag local-caddy -f build.Dockerfile .

if [[ $? -ne 0 ]]; then
  exit 1
fi

if [[ -z "$CADDY_LOG_DIR" ]]; then
  CADDY_LOG_DIR="$HOME/caddy/log"
fi
mkdir -p "$CADDY_LOG_DIR"

if [[ -z "$CADDY_DATA_DIR" ]]; then
  CADDY_DATA_DIR="$HOME/caddy/data"
fi
mkdir -p "$CADDY_DATA_DIR"

if [[ "root" == "$(id -un)" ]]; then
  SYSTEMD_SERVICE_DIR=/lib/systemd/system
else
  SYSTEMD_SERVICE_DIR="$HOME/.config/systemd/user"
  mkdir -p "$SYSTEMD_SERVICE_DIR"
fi

if [[ "$SYSTEMD_SERVICE_DIR" == "/lib/systemd/system" ]]; then
  systemctl --all | grep -F proxy-caddy.service >/dev/null 2>&1
  if [ $? -eq 0 ]; then
    systemctl stop proxy-caddy.service
    systemctl disable proxy-caddy.service
  fi
else
  export XDG_RUNTIME_DIR="/run/user/$UID"
  export DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR}/bus"

  # Maybe need run from host: loginctl enable-linger tools
  # see https://wiki.archlinux.org/index.php/Systemd/User
  # sudo loginctl enable-linger $RUN_USER
  systemctl --user --all | grep -F proxy-caddy.service >/dev/null 2>&1
  if [ $? -eq 0 ]; then
    systemctl --user stop proxy-caddy.service
    systemctl --user disable proxy-caddy.service
  fi
fi

podman container inspect proxy-caddy >/dev/null 2>&1

if [[ $? -eq 0 ]]; then
  podman stop proxy-caddy
  podman rm -f proxy-caddy
fi

if [[ "x$CADDY_UPDATE" != "x" ]] || [[ "x$ROUTER_IMAGE_UPDATE" != "x" ]]; then
  podman image prune -a -f --filter "until=240h"
fi

podman run -d --name proxy-caddy --security-opt label=disable \
  ${PODMAN_COMMON_OPTIONS[@]} \
  --cap-add=NET_ADMIN --cap-add=NET_BIND_SERVICE \
  --mount type=bind,source=$CADDY_LOG_DIR,target=/var/log/caddy \
  --mount type=bind,source=$CADDY_DATA_DIR,target=/data/caddy \
  -e "DNSPOD_TOKEN=$PROXY_CADDY_DNSPOD_TOKEN" \
  -e "CF_API_TOKEN=$PROXY_CADDY_CLOUDFLARE_API_TOKEN" \
  --network=host local-caddy

podman generate systemd proxy-caddy | tee -p "$SYSTEMD_SERVICE_DIR/proxy-caddy.service"
podman container stop proxy-caddy

if [[ "$SYSTEMD_SERVICE_DIR" == "/lib/systemd/system" ]]; then
  systemctl enable proxy-caddy.service
  systemctl daemon-reload
  systemctl start proxy-caddy.service
else
  systemctl --user enable "$SYSTEMD_SERVICE_DIR/proxy-caddy.service"
  systemctl --user daemon-reload
  systemctl --user start proxy-caddy.service
fi
