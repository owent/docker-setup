#!/bin/bash

# $ROUTER_HOME/sing-box/create-client-pod.sh

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"

if [[ -z "$VBOX_CADDY_ETC_DIR" ]]; then
  VBOX_CADDY_ETC_DIR="$HOME/vbox/etc-caddy"
fi
if [[ -z "$VBOX_CADDY_IMAGE_URL" ]]; then
  VBOX_CADDY_IMAGE_URL="docker.io/caddy:latest"
fi

mkdir -p "$VBOX_CADDY_ETC_DIR"

if [[ "x$VBOX_UPDATE" != "x" ]] || [[ "x$ROUTER_IMAGE_UPDATE" != "x" ]]; then
  podman pull "$VBOX_CADDY_IMAGE_URL"
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
  systemctl --all | grep -F vbox-caddy-fallback.service >/dev/null 2>&1
  if [ $? -eq 0 ]; then
    systemctl stop vbox-caddy-fallback.service
    systemctl disable vbox-caddy-fallback.service
  fi

  # Remove old systemd service
  if [[ -e "$SYSTEMD_SERVICE_DIR/vproxy-caddy-fallback.service" ]]; then
    systemctl stop vproxy-caddy-fallback.service
    systemctl disable vproxy-caddy-fallback.service
    rm "$SYSTEMD_SERVICE_DIR/vproxy-caddy-fallback.service"
  fi
else
  export XDG_RUNTIME_DIR="/run/user/$UID"
  export DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR}/bus"

  # Maybe need run from host: loginctl enable-linger tools
  # see https://wiki.archlinux.org/index.php/Systemd/User
  # sudo loginctl enable-linger $RUN_USER
  systemctl --user --all | grep -F vbox-caddy-fallback.service >/dev/null 2>&1
  if [ $? -eq 0 ]; then
    systemctl --user stop vbox-caddy-fallback.service
    systemctl --user disable vbox-caddy-fallback.service
  fi

  # Remove old systemd service
  if [[ -e "$SYSTEMD_SERVICE_DIR/vproxy-caddy-fallback.service" ]]; then
    systemctl --user stop vproxy-caddy-fallback.service
    systemctl --user disable vproxy-caddy-fallback.service
    rm "$SYSTEMD_SERVICE_DIR/vproxy-caddy-fallback.service"
  fi
fi

podman container inspect vbox-caddy-fallback >/dev/null 2>&1
if [[ $? -eq 0 ]]; then
  podman stop vbox-caddy-fallback
  podman rm -f vbox-caddy-fallback
fi

# Remove old pods
podman container inspect vproxy-caddy-fallback >/dev/null 2>&1
if [[ $? -eq 0 ]]; then
  podman stop vproxy-caddy-fallback
  podman rm -f vproxy-caddy-fallback
fi

if [[ "x$VBOX_UPDATE" != "x" ]] || [[ "x$ROUTER_IMAGE_UPDATE" != "x" ]]; then
  podman image prune -a -f --filter "until=240h"
fi

echo "
{
  auto_https off
  servers :8375 {
    protocols h1 h2 h2c h3
  }
}
:8375 {
  header Content-Type \"text/html; charset=utf-8\"
  redir https://owent.net{uri} html
}
" >"$VBOX_CADDY_ETC_DIR/Caddyfile"

podman run -d --name vbox-caddy-fallback --security-opt label=disable \
  -v $VBOX_CADDY_ETC_DIR/Caddyfile:/etc/caddy/Caddyfile \
  --network=host $VBOX_CADDY_IMAGE_URL \
  caddy run --config /etc/caddy/Caddyfile

if [[ $? -ne 0 ]]; then
  exit $?
fi

podman generate systemd vbox-caddy-fallback | tee -p "$SYSTEMD_SERVICE_DIR/vbox-caddy-fallback.service"
podman container stop vbox-caddy-fallback

if [[ "$SYSTEMD_SERVICE_DIR" == "/lib/systemd/system" ]]; then
  systemctl enable vbox-caddy-fallback.service
  systemctl daemon-reload
  systemctl start vbox-caddy-fallback.service
else
  systemctl --user enable "$SYSTEMD_SERVICE_DIR/vbox-caddy-fallback.service"
  systemctl --user daemon-reload
  systemctl --user start vbox-caddy-fallback.service
fi
