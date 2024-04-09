#!/bin/bash

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"

if [[ "x$KEA_ETC_DIR" == "x" ]]; then
  KEA_ETC_DIR="$SCRIPT_DIR/etc"
fi
mkdir -p "$KEA_ETC_DIR"

if [[ "x$KEA_DATA_DIR" == "x" ]]; then
  KEA_DATA_DIR="$SCRIPT_DIR/data"
fi
mkdir -p "$KEA_DATA_DIR"

if [[ ! -e "$KEA_ETC_DIR/kea-dhcp4.conf" ]]; then
  cp -f "$SCRIPT_DIR/sample.kea.conf" "$KEA_ETC_DIR/kea-dhcp4.conf"
fi
if [[ ! -e "$KEA_ETC_DIR/kea-ctrl-agent.conf" ]]; then
  cp -f "$SCRIPT_DIR/kea-ctrl-agent.conf" "$KEA_ETC_DIR/kea-ctrl-agent.conf"
fi

if [[ "root" == "$(id -un)" ]]; then
  SYSTEMD_SERVICE_DIR=/lib/systemd/system
else
  SYSTEMD_SERVICE_DIR="$HOME/.config/systemd/user"
  mkdir -p "$SYSTEMD_SERVICE_DIR"
fi

if [[ "$SYSTEMD_SERVICE_DIR" == "/lib/systemd/system" ]]; then
  systemctl --all | grep -F kea-dhcp4.service >/dev/null 2>&1
  if [ $? -eq 0 ]; then
    systemctl stop kea-dhcp4.service
    systemctl disable kea-dhcp4.service
  fi
else
  export XDG_RUNTIME_DIR="/run/user/$UID"
  export DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR}/bus"

  # Maybe need run from host: loginctl enable-linger tools
  # see https://wiki.archlinux.org/index.php/Systemd/User
  # sudo loginctl enable-linger $(id -un)
  systemctl --user --all | grep -F kea-dhcp4.service >/dev/null 2>&1
  if [ $? -eq 0 ]; then
    systemctl --user stop kea-dhcp4.service
    systemctl --user disable kea-dhcp4.service
  fi
fi

if [[ "x$KEA_UPDATE" != "x" ]] || [[ "x$ROUTER_IMAGE_UPDATE" != "x" ]]; then
  # podman pull docker.cloudsmith.io/isc/docker/kea-dhcp4:latest
  podman pull docker.io/alpine:latest
  if [[ $? -ne 0 ]]; then
    exit 1
  fi
fi

podman build --tag local-kea -f kea-dhcp4.Dockerfile .
if [[ $? -ne 0 ]]; then
  exit 1
fi

podman inspect kea-dhcp4 >/dev/null 2>&1
if [[ $? -eq 0 ]]; then
  podman stop kea-dhcp4 || true
  podman rm kea-dhcp4 || true
fi

if [[ "x$KEA_UPDATE" != "x" ]] || [[ "x$ROUTER_IMAGE_UPDATE" != "x" ]]; then
  podman image prune -a -f --filter "until=240h"
fi

podman run -d --name kea-dhcp4 --cap-add NET_BIND_SERVICE --cap-add NET_RAW \
  --security-opt label=disable --security-opt seccomp=unconfined \
  --network=host \
  --mount type=bind,source=$KEA_ETC_DIR,target=/etc/kea \
  --mount type=bind,source=$KEA_DATA_DIR,target=/var/lib/kea \
  local-kea /usr/sbin/kea-dhcp4 -c /etc/kea/kea-dhcp4.conf

podman generate systemd kea-dhcp4 | tee "$SYSTEMD_SERVICE_DIR/kea-dhcp4.service"
podman container stop kea-dhcp4

if [[ "$SYSTEMD_SERVICE_DIR" == "/lib/systemd/system" ]]; then
  systemctl daemon-reload
  systemctl enable kea-dhcp4.service
  systemctl start kea-dhcp4.service
else
  systemctl --user daemon-reload
  systemctl --user enable "$SYSTEMD_SERVICE_DIR/kea-dhcp4.service"
  systemctl --user start kea-dhcp4.service
fi
