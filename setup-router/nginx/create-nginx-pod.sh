#!/bin/bash

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
source "$(dirname "$SCRIPT_DIR")/configure-router.sh"

# Require net.ipv4.ip_unprivileged_port_start=80 in /etc/sysctl.d/*.conf
# See https://github.com/containers/podman/blob/master/rootless.md

if [[ "root" == "$(id -un)" ]]; then
  SYSTEMD_SERVICE_DIR=/lib/systemd/system
else
  SYSTEMD_SERVICE_DIR="$HOME/.config/systemd/user"
  mkdir -p "$SYSTEMD_SERVICE_DIR"
fi

if [[ "$SYSTEMD_SERVICE_DIR" == "/lib/systemd/system" ]]; then
  systemctl --all | grep -F nginx.service >/dev/null 2>&1
  if [ $? -eq 0 ]; then
    systemctl stop nginx.service
    systemctl disable nginx.service
  fi
else
  export XDG_RUNTIME_DIR="/run/user/$UID"
  export DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR}/bus"

  # Maybe need run from host: loginctl enable-linger tools
  # see https://wiki.archlinux.org/index.php/Systemd/User
  # sudo loginctl enable-linger $RUN_USER
  systemctl --user --all | grep -F nginx.service >/dev/null 2>&1
  if [ $? -eq 0 ]; then
    systemctl --user stop nginx.service
    systemctl --user disable nginx.service
  fi
fi

if [[ "x$NGINX_UPDATE" != "x" ]] || [[ "x$ROUTER_IMAGE_UPDATE" != "x" ]]; then
  podman pull docker.io/nginx:latest
fi

podman container exists nginx
if [[ $? -eq 0 ]]; then
  podman stop nginx
  podman rm -f nginx
fi

mkdir -p /home/website/log/nginx

if [[ "x$NGINX_UPDATE" != "x" ]]; then
  podman image prune -a -f --filter "until=240h"
fi

podman run -d --name nginx --security-opt label=disable \
  --mount type=bind,source=/home/website/log,target=/home/website/log \
  --mount type=bind,source=/home/website/home,target=/home/website/home,ro=true \
  --mount type=bind,source=/home/website/ssl,target=/home/website/ssl,ro=true \
  --mount type=bind,source=/home/website/etc/nginx.conf,target=/etc/nginx/nginx.conf \
  --mount type=bind,source=/home/website/etc/conf.d,target=/etc/nginx/conf.d \
  --network=host \
  docker.io/nginx:latest

# Some system with old slirp4netns do not work, debian 10 for example, so we use --network=host here
# -p 80:80/tcp -p 80:80/udp -p 443:443/tcp -p 443:443/udp                                    \
if [[ $? -ne 0 ]]; then
  exit $?
fi

podman generate systemd nginx | tee -p "$SYSTEMD_SERVICE_DIR/nginx.service"
podman container stop nginx

if [[ "$SYSTEMD_SERVICE_DIR" == "/lib/systemd/system" ]]; then
  systemctl enable nginx.service
  systemctl daemon-reload
  systemctl start nginx.service
else
  systemctl --user enable "$SYSTEMD_SERVICE_DIR/nginx.service"
  systemctl --user daemon-reload
  systemctl --user start nginx.service
fi
