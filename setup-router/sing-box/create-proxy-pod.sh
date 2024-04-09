#!/bin/bash

# $ROUTER_HOME/sing-box/create-client-pod.sh

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"

if [[ -z "$VBOX_ETC_DIR" ]]; then
  VBOX_ETC_DIR="$HOME/vbox/etc"
fi
if [[ -z "$VBOX_DATA_DIR" ]]; then
  VBOX_DATA_DIR="$HOME/vbox/data"
fi
if [[ -z "$VBOX_LOG_DIR" ]]; then
  VBOX_LOG_DIR="$HOME/vbox/log"
fi

mkdir -p "$VBOX_ETC_DIR"
mkdir -p "$VBOX_DATA_DIR"
mkdir -p "$VBOX_LOG_DIR"

if [[ "x$VBOX_UPDATE" != "x" ]] || [[ "x$ROUTER_IMAGE_UPDATE" != "x" ]]; then
  podman pull docker.io/owt5008137/vbox:latest
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
  systemctl --all | grep -F vbox-proxy.service >/dev/null 2>&1
  if [ $? -eq 0 ]; then
    systemctl stop vbox-proxy.service
    systemctl disable vbox-proxy.service
  fi
else
  export XDG_RUNTIME_DIR="/run/user/$UID"
  export DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR}/bus"

  # Maybe need run from host: loginctl enable-linger tools
  # see https://wiki.archlinux.org/index.php/Systemd/User
  # sudo loginctl enable-linger $RUN_USER
  systemctl --user --all | grep -F vbox-proxy.service >/dev/null 2>&1
  if [ $? -eq 0 ]; then
    systemctl --user stop vbox-proxy.service
    systemctl --user disable vbox-proxy.service
  fi
fi

podman container inspect vbox-proxy >/dev/null 2>&1
if [[ $? -eq 0 ]]; then
  podman stop vbox-proxy
  podman rm -f vbox-proxy
fi

if [[ "x$VBOX_UPDATE" != "x" ]] || [[ "x$ROUTER_IMAGE_UPDATE" != "x" ]]; then
  podman image prune -a -f --filter "until=240h"
fi

podman run -d --name vbox-proxy --cap-add=NET_BIND_SERVICE \
  --network=host --security-opt label=disable \
  --mount type=bind,source=$VBOX_ETC_DIR,target=/etc/vbox/,ro=true \
  --mount type=bind,source=$VBOX_DATA_DIR,target=/var/lib/vbox \
  --mount type=bind,source=$VBOX_LOG_DIR,target=/var/log/vbox \
  docker.io/owt5008137/vbox:latest -D /var/lib/vbox -C /etc/vbox/ run

# podman cp vbox-proxy:/usr/local/vbox-proxy/share/geo-all.tar.gz geo-all.tar.gz
# if [[ $? -eq 0 ]]; then
#   tar -axvf geo-all.tar.gz
#   if [ $? -eq 0 ]; then
#     bash "$SCRIPT_DIR/setup-geoip-geosite.sh"
#   fi
# fi

podman generate systemd vbox-proxy | tee $SYSTEMD_SERVICE_DIR/vbox-proxy.service

podman container stop vbox-proxy

if [[ "$SYSTEMD_SERVICE_DIR" == "/lib/systemd/system" ]]; then
  systemctl enable vbox-proxy.service
  systemctl daemon-reload
  systemctl start vbox-proxy.service
else
  systemctl --user enable "$SYSTEMD_SERVICE_DIR/vbox-proxy.service"
  systemctl --user daemon-reload
  systemctl --user start vbox-proxy.service
fi
