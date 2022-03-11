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
  RUN_USER=tools
fi
RUN_HOME=$(cat /etc/passwd | awk "BEGIN{FS=\":\"} \$1 == \"$RUN_USER\" { print \$6 }")

if [[ "x$RUN_HOME" == "x" ]]; then
  RUN_HOME="$HOME"
  RUN_USER=$(whoami)
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

if [[ "root" == "$(whoami)" ]]; then
  SYSTEMD_SERVICE_DIR=/lib/systemd/system
else
  SYSTEMD_SERVICE_DIR="$HOME/.config/systemd/user"
  mkdir -p "$SYSTEMD_SERVICE_DIR"
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
  systemctl --user --all | grep -F v2ray-proxy-with-geo.service >/dev/null 2>&1
  if [ $? -eq 0 ]; then
    systemctl --user stop v2ray-proxy-with-geo.service
    systemctl --user disable v2ray-proxy-with-geo.service
  fi
fi

podman container inspect v2ray-proxy-with-geo >/dev/null 2>&1
if [[ $? -eq 0 ]]; then
  podman stop v2ray-proxy-with-geo
  podman rm -f v2ray-proxy-with-geo
fi

if [[ "x$V2RAY_UPDATE" != "x" ]]; then
  podman image inspect docker.io/owt5008137/proxy-with-geo:latest >/dev/null 2>&1
  if [[ $? -eq 0 ]]; then
    podman image rm -f docker.io/owt5008137/proxy-with-geo:latest
  fi
fi

podman pull docker.io/owt5008137/proxy-with-geo:latest

podman run -d --name v2ray-proxy-with-geo --security-opt label=disable \
  --mount type=bind,source=$V2RAY_ETC_DIR,target=/usr/local/v2ray/etc,ro=true \
  --mount type=bind,source=$V2RAY_LOG_DIR,target=/usr/local/v2ray/log \
  --mount type=bind,source=$V2RAY_SSL_DIR,target=/home/website/ssl,ro=true \
  -p 8371-8373:8371-8373/tcp -p 8371-8373:8371-8373/udp \
  docker.io/owt5008137/proxy-with-geo:latest v2ray "-config=/usr/local/v2ray/etc/config.json"

if [[ $? -ne 0 ]]; then
  exit $?
fi

podman generate systemd v2ray-proxy-with-geo | tee -p "$SYSTEMD_SERVICE_DIR/v2ray-proxy-with-geo.service"
podman container stop v2ray-proxy-with-geo

if [[ "$SYSTEMD_SERVICE_DIR" == "/lib/systemd/system" ]]; then
  systemctl enable v2ray-proxy-with-geo.service
  systemctl daemon-reload
  systemctl start v2ray-proxy-with-geo.service
else
  systemctl --user enable "$SYSTEMD_SERVICE_DIR/v2ray-proxy-with-geo.service"
  systemctl --user daemon-reload
  systemctl --user start v2ray-proxy-with-geo.service
fi
