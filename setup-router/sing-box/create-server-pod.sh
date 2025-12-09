#!/bin/bash

# $ROUTER_HOME/sing-box/create-client-pod.sh

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"

DOCKER_EXEC=$((which podman > /dev/null 2>&1 && echo podman) || (which docker > /dev/null 2>&1 && echo docker))

if [[ -z "$VBOX_ETC_DIR" ]]; then
  VBOX_ETC_DIR="$HOME/vbox/etc"
fi
if [[ -z "$VBOX_DATA_DIR" ]]; then
  VBOX_DATA_DIR="$HOME/vbox/data"
fi
if [[ -z "$VBOX_LOG_DIR" ]]; then
  VBOX_LOG_DIR="$HOME/vbox/log"
fi
if [[ -z "$VBOX_IMAGE_URL" ]]; then
  VBOX_IMAGE_URL="ghcr.io/owent/vbox:latest"
fi

mkdir -p "$VBOX_ETC_DIR"
mkdir -p "$VBOX_DATA_DIR"
mkdir -p "$VBOX_LOG_DIR"

if [[ "x$VBOX_UPDATE" != "x" ]] || [[ "x$ROUTER_IMAGE_UPDATE" != "x" ]]; then
  $DOCKER_EXEC pull "$VBOX_IMAGE_URL"
  if [[ $? -ne 0 ]]; then
    exit 1
  fi
fi

if [[ "root" == "$(id -un)" ]]; then
  SYSTEMD_SERVICE_DIR=/lib/systemd/system
else
  SYSTEMD_SERVICE_DIR="$HOME/.config/systemd/user"
  mkdir -p "$SYSTEMD_SERVICE_DIR"
fi

if [[ "$SYSTEMD_SERVICE_DIR" == "/lib/systemd/system" ]]; then
  systemctl --all | grep -F vbox-server.service >/dev/null 2>&1
  if [ $? -eq 0 ]; then
    systemctl stop vbox-server.service
    systemctl disable vbox-server.service
  fi
else
  export XDG_RUNTIME_DIR="/run/user/$UID"
  export DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR}/bus"

  # Maybe need run from host: loginctl enable-linger tools
  # see https://wiki.archlinux.org/index.php/Systemd/User
  # sudo loginctl enable-linger $RUN_USER
  systemctl --user --all | grep -F vbox-server.service >/dev/null 2>&1
  if [ $? -eq 0 ]; then
    systemctl --user stop vbox-server.service
    systemctl --user disable vbox-server.service
  fi
fi

$DOCKER_EXEC container inspect vbox-server >/dev/null 2>&1
if [[ $? -eq 0 ]]; then
  $DOCKER_EXEC stop vbox-server
  $DOCKER_EXEC rm -f vbox-server
fi

if [[ "x$VBOX_UPDATE" != "x" ]] || [[ "x$ROUTER_IMAGE_UPDATE" != "x" ]]; then
  $DOCKER_EXEC image prune -a -f --filter "until=240h"
fi

VBOX_DOCKER_OPRIONS=(
  --cap-add=NET_BIND_SERVICE
  --network=host --security-opt label=disable
  --mount type=bind,source=$VBOX_DATA_DIR,target=/var/lib/vbox
  --mount type=bind,source=$VBOX_LOG_DIR,target=/var/log/vbox
  --mount type=bind,source=$VBOX_ETC_DIR,target=/etc/vbox,ro=true
)

if [[ ! -z "$VBOX_SSL_DIR" ]]; then
  VBOX_DOCKER_OPRIONS=("${VBOX_DOCKER_OPRIONS[@]}" --mount type=bind,source=$VBOX_SSL_DIR,target=$VBOX_SSL_DIR,ro=true)
fi

$DOCKER_EXEC run -d --name vbox-server "${VBOX_DOCKER_OPRIONS[@]}" \
  "$VBOX_IMAGE_URL" -D /var/lib/vbox -C /etc/vbox/ run

if [[ $? -ne 0 ]]; then
  exit 1
fi

# $DOCKER_EXEC cp vbox-server:/usr/local/vbox-server/share/geo-all.tar.gz geo-all.tar.gz
# if [[ $? -eq 0 ]]; then
#   tar -axvf geo-all.tar.gz
#   if [ $? -eq 0 ]; then
#     bash "$SCRIPT_DIR/setup-geoip-geosite.sh"
#   fi
# fi

$DOCKER_EXEC exec vbox-proxy ln -f /usr/share/zoneinfo/Asia/Shanghai /etc/timezone

$DOCKER_EXEC generate systemd vbox-server | tee $SYSTEMD_SERVICE_DIR/vbox-server.service

$DOCKER_EXEC container stop vbox-server

if [[ "$SYSTEMD_SERVICE_DIR" == "/lib/systemd/system" ]]; then
  systemctl enable vbox-server.service
  systemctl daemon-reload
  systemctl start vbox-server.service
else
  systemctl --user enable "$SYSTEMD_SERVICE_DIR/vbox-server.service"
  systemctl --user daemon-reload
  systemctl --user start vbox-server.service
fi

if [[ -e "$SCRIPT_DIR/create-caddy-fallback-pod.sh" ]]; then
  bash "$SCRIPT_DIR/create-caddy-fallback-pod.sh"
fi
