#!/bin/bash

# Maybe need in /etc/ssh/sshd_config
#     DenyUsers tools
#     DenyGroups tools

if [[ -e "/opt/nftables/sbin" ]]; then
  export PATH=/opt/nftables/sbin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/bin/site_perl:/usr/bin/vendor_perl:/usr/bin/core_perl
else
  export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/bin/site_perl:/usr/bin/vendor_perl:/usr/bin/core_perl
fi

if [[ "x$V2RAY_SSL_DIR" == "x" ]] && [[ -e "/home/website/ssl/" ]]; then
  V2RAY_SSL_DIR="/home/website/ssl/"
fi

if [[ "x$RUN_USER" == "x" ]]; then
  RUN_USER=$(id -un)
fi
RUN_HOME=$(cat /etc/passwd | awk "BEGIN{FS=\":\"} \$1 == \"$RUN_USER\" { print \$6 }")

if [[ "x$RUN_HOME" == "x" ]]; then
  RUN_HOME="$HOME"
fi

if [[ "x$V2RAY_ETC_DIR" == "x" ]]; then
  V2RAY_ETC_DIR="$RUN_HOME/v2ray/etc"
fi
mkdir -p "$V2RAY_ETC_DIR"
if [[ "x$V2RAY_LOG_DIR" == "x" ]]; then
  V2RAY_LOG_DIR="$RUN_HOME/v2ray/log"
fi
mkdir -p "$V2RAY_LOG_DIR"
if [[ "x$V2RAY_SSL_DIR" == "x" ]]; then
  V2RAY_SSL_DIR="$RUN_HOME/v2ray/ssl"
fi
mkdir -p "$V2RAY_SSL_DIR"

cd "$(dirname "${BASH_SOURCE[0]}")"

if [[ "root" == "$(id -un)" ]]; then
  SYSTEMD_SERVICE_DIR=/lib/systemd/system
else
  SYSTEMD_SERVICE_DIR="$HOME/.config/systemd/user"
  mkdir -p "$SYSTEMD_SERVICE_DIR"
fi

if [[ "x$V2RAY_UPDATE" != "x" ]] || [[ "x$HOME_ROUTER_UPDATE" != "x" ]]; then
  podman pull docker.io/caddy:latest
  podman pull docker.io/owt5008137/proxy-with-geo:latest
fi

if [[ "$SYSTEMD_SERVICE_DIR" == "/lib/systemd/system" ]]; then
  systemctl --all | grep -F v2ray-proxy-with-geo.service >/dev/null 2>&1
  if [[ $? -eq 0 ]]; then
    systemctl stop v2ray-proxy-with-geo.service
    systemctl disable v2ray-proxy-with-geo.service
  fi
else
  export XDG_RUNTIME_DIR="/run/user/$UID"
  export DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR}/bus"
  # Maybe need run from host: loginctl enable-linger tools
  # see https://wiki.archlinux.org/index.php/Systemd/User
  # sudo loginctl enable-linger $RUN_USER

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
fi

# Caddy fallback server
podman container inspect v2ray-caddy-fallback >/dev/null 2>&1
if [[ $? -eq 0 ]]; then
  podman stop v2ray-caddy-fallback
  podman rm -f v2ray-caddy-fallback
fi

echo "
{
  auto_https off
  servers :8375 {
    protocol {
      allow_h2c
    }
  }
}
http://localhost:8375 http://127.0.0.1:8375 http://*.shkits.com:8375 {
  redir https://owent.net{uri} html
}
" >"$V2RAY_ETC_DIR/Caddyfile"
podman run -d --name v2ray-caddy-fallback --security-opt label=disable \
  -v $V2RAY_ETC_DIR/Caddyfile:/etc/caddy/Caddyfile \
  --network=host docker.io/caddy:latest \
  caddy run -config /etc/caddy/Caddyfile

if [[ $? -ne 0 ]]; then
  exit $?
fi

podman generate systemd v2ray-caddy-fallback | tee -p "$SYSTEMD_SERVICE_DIR/v2ray-caddy-fallback.service"
podman container stop v2ray-caddy-fallback

# v2ray
podman container inspect v2ray-proxy-with-geo >/dev/null 2>&1
if [[ $? -eq 0 ]]; then
  podman stop v2ray-proxy-with-geo
  podman rm -f v2ray-proxy-with-geo
fi

podman run -d --name v2ray-proxy-with-geo --security-opt label=disable \
  --mount type=bind,source=$V2RAY_ETC_DIR,target=/usr/local/v2ray/etc,ro=true \
  --mount type=bind,source=$V2RAY_LOG_DIR,target=/usr/local/v2ray/log \
  --mount type=bind,source=$V2RAY_SSL_DIR,target=/home/website/ssl,ro=true \
  --network=host \
  docker.io/owt5008137/proxy-with-geo:latest v2ray "-config=/usr/local/v2ray/etc/config.json"

if [[ $? -ne 0 ]]; then
  exit $?
fi

podman generate systemd v2ray-proxy-with-geo | tee -p "$SYSTEMD_SERVICE_DIR/v2ray-proxy-with-geo.service"
podman container stop v2ray-proxy-with-geo

if [[ "x$V2RAY_UPDATE" != "x" ]] || [[ "x$HOME_ROUTER_UPDATE" != "x" ]]; then
  podman image prune -a -f --filter "until=240h"
fi

if [[ "$SYSTEMD_SERVICE_DIR" == "/lib/systemd/system" ]]; then
  systemctl enable v2ray-proxy-with-geo.service
  systemctl enable v2ray-caddy-fallback.service
  systemctl daemon-reload
  systemctl restart v2ray-proxy-with-geo.service
  systemctl restart v2ray-caddy-fallback.service
else
  systemctl --user enable "$SYSTEMD_SERVICE_DIR/v2ray-proxy-with-geo.service"
  systemctl --user enable "$SYSTEMD_SERVICE_DIR/v2ray-caddy-fallback.service"
  systemctl --user daemon-reload
  systemctl --user restart v2ray-proxy-with-geo.service
  systemctl --user restart v2ray-caddy-fallback.service
fi
