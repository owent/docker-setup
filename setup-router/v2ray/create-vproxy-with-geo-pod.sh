#!/bin/bash

# Maybe need in /etc/ssh/sshd_config
#     DenyUsers tools
#     DenyGroups tools

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
if [[ -e "$(dirname "$SCRIPT_DIR")/configure-router.sh" ]]; then
  source "$(dirname "$SCRIPT_DIR")/configure-router.sh"
fi

if [[ "x$RUN_USER" == "x" ]]; then
  RUN_USER=$(id -un)
fi
RUN_HOME=$(cat /etc/passwd | awk "BEGIN{FS=\":\"} \$1 == \"$RUN_USER\" { print \$6 }")

if [[ "x$RUN_HOME" == "x" ]]; then
  RUN_HOME="$HOME"
fi

if [[ "x$VPROXY_ETC_DIR" == "x" ]]; then
  VPROXY_ETC_DIR="$V2RAY_ETC_DIR"
fi
if [[ "x$VPROXY_ETC_DIR" == "x" ]]; then
  VPROXY_ETC_DIR="$RUN_HOME/vproxy/etc"
fi
mkdir -p "$VPROXY_ETC_DIR"
if [[ "x$VPROXY_LOG_DIR" == "x" ]]; then
  VPROXY_LOG_DIR="$V2RAY_LOG_DIR"
fi
if [[ "x$VPROXY_LOG_DIR" == "x" ]]; then
  VPROXY_LOG_DIR="$RUN_HOME/vproxy/log"
fi
mkdir -p "$VPROXY_LOG_DIR"
if [[ "x$VPROXY_SSL_DIR" == "x" ]]; then
  VPROXY_SSL_DIR="$V2RAY_SSL_DIR"
fi
if [[ "x$VPROXY_SSL_DIR" == "x" ]]; then
  if [[ -e "/home/website/ssl/" ]]; then
    VPROXY_SSL_DIR="/home/website/ssl/"
  else
    VPROXY_SSL_DIR="$RUN_HOME/vproxy/ssl"
  fi
fi
mkdir -p "$VPROXY_SSL_DIR"

cd "$(dirname "${BASH_SOURCE[0]}")"

if [[ "root" == "$(id -un)" ]]; then
  SYSTEMD_SERVICE_DIR=/lib/systemd/system
else
  SYSTEMD_SERVICE_DIR="$HOME/.config/systemd/user"
  mkdir -p "$SYSTEMD_SERVICE_DIR"
fi

if [[ "x$V2RAY_UPDATE" != "x" ]] || [[ "x$VPROXY_UPDATE" != "x" ]] || [[ "x$ROUTER_IMAGE_UPDATE" != "x" ]]; then
  podman pull docker.io/caddy:latest
  if [[ $? -ne 0 ]]; then
    exit 1
  fi
  podman pull docker.io/owt5008137/proxy-with-geo:latest
  if [[ $? -ne 0 ]]; then
    exit 1
  fi
fi

if [[ "$SYSTEMD_SERVICE_DIR" == "/lib/systemd/system" ]]; then
  # Legacy name
  systemctl --all | grep -F v2ray-proxy-with-geo.service >/dev/null 2>&1
  if [[ $? -eq 0 ]]; then
    systemctl stop v2ray-proxy-with-geo.service
    systemctl disable v2ray-proxy-with-geo.service
  fi

  # New name
  systemctl --all | grep -F vproxy-with-geo.service >/dev/null 2>&1
  if [[ $? -eq 0 ]]; then
    systemctl stop vproxy-with-geo.service
    systemctl disable vproxy-with-geo.service
  fi
else
  export XDG_RUNTIME_DIR="/run/user/$UID"
  export DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR}/bus"
  # Maybe need run from host: loginctl enable-linger tools
  # see https://wiki.archlinux.org/index.php/Systemd/User
  # sudo loginctl enable-linger $RUN_USER

  # Legacy name
  systemctl --user --all | grep -F v2ray-caddy-fallback.service >/dev/null 2>&1
  if [ $? -eq 0 ]; then
    systemctl --user stop v2ray-caddy-fallback.service
    systemctl --user disable v2ray-caddy-fallback.service
  fi

  systemctl --user --all | grep -F v2ray-proxy-with-geo.service >/dev/null 2>&1
  if [ $? -eq 0 ]; then
    systemctl --user stop v2ray-proxy-with-geo.service
    systemctl --user disable v2ray-proxy-with-geo.service
  fi

  # New name
  systemctl --user --all | grep -F vproxy-caddy-fallback.service >/dev/null 2>&1
  if [ $? -eq 0 ]; then
    systemctl --user stop vproxy-caddy-fallback.service
    systemctl --user disable vproxy-caddy-fallback.service
  fi

  systemctl --user --all | grep -F vproxy-with-geo.service >/dev/null 2>&1
  if [ $? -eq 0 ]; then
    systemctl --user stop vproxy-with-geo.service
    systemctl --user disable vproxy-with-geo.service
  fi
fi

# Caddy fallback server(Legacy name)
podman container exists v2ray-caddy-fallback
if [[ $? -eq 0 ]]; then
  podman stop v2ray-caddy-fallback
  podman rm -f v2ray-caddy-fallback
fi

# Caddy fallback server(New name)
podman container exists vproxy-caddy-fallback
if [[ $? -eq 0 ]]; then
  podman stop vproxy-caddy-fallback
  podman rm -f vproxy-caddy-fallback
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
" >"$VPROXY_ETC_DIR/Caddyfile"
podman run -d --name vproxy-caddy-fallback --security-opt label=disable \
  -v $VPROXY_ETC_DIR/Caddyfile:/etc/caddy/Caddyfile \
  --network=host docker.io/caddy:latest \
  caddy run --config /etc/caddy/Caddyfile

if [[ $? -ne 0 ]]; then
  exit $?
fi

podman generate systemd vproxy-caddy-fallback | tee -p "$SYSTEMD_SERVICE_DIR/vproxy-caddy-fallback.service"
podman container stop vproxy-caddy-fallback

# proxy
podman container exists vproxy-with-geo
if [[ $? -eq 0 ]]; then
  podman stop vproxy-with-geo
  podman rm -f vproxy-with-geo
fi

podman run -d --name vproxy-with-geo --security-opt label=disable \
  --mount type=bind,source=$VPROXY_ETC_DIR,target=/usr/local/vproxy/etc,ro=true \
  --mount type=bind,source=$VPROXY_LOG_DIR,target=/usr/local/vproxy/log \
  --mount type=bind,source=$VPROXY_SSL_DIR,target=/home/website/ssl,ro=true \
  --network=host \
  docker.io/owt5008137/proxy-with-geo:latest vproxyd run "-c" "/usr/local/vproxy/etc/config.json"

if [[ $? -ne 0 ]]; then
  exit $?
fi

podman generate systemd vproxy-with-geo | tee -p "$SYSTEMD_SERVICE_DIR/vproxy-with-geo.service"
podman container stop vproxy-with-geo

if [[ "x$V2RAY_UPDATE" != "x" ]] || [[ "x$VPROXY_UPDATE" != "x" ]] || [[ "x$ROUTER_IMAGE_UPDATE" != "x" ]]; then
  podman image prune -a -f --filter "until=240h"
fi

if [[ "$SYSTEMD_SERVICE_DIR" == "/lib/systemd/system" ]]; then
  systemctl enable vproxy-with-geo.service
  systemctl enable vproxy-caddy-fallback.service
  systemctl daemon-reload
  systemctl restart vproxy-with-geo.service
  systemctl restart vproxy-caddy-fallback.service
else
  systemctl --user enable "$SYSTEMD_SERVICE_DIR/vproxy-with-geo.service"
  systemctl --user enable "$SYSTEMD_SERVICE_DIR/vproxy-caddy-fallback.service"
  systemctl --user daemon-reload
  systemctl --user restart vproxy-with-geo.service
  systemctl --user restart vproxy-caddy-fallback.service
fi
