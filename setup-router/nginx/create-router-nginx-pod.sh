#!/bin/bash

if [[ -e "/opt/nftables/sbin" ]]; then
  export PATH=/opt/nftables/sbin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/bin/site_perl:/usr/bin/vendor_perl:/usr/bin/core_perl
else
  export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/bin/site_perl:/usr/bin/vendor_perl:/usr/bin/core_perl
fi

if [[ "x$ROUTER_HOME" == "x" ]]; then
  source "$(cd "$(dirname "$0")" && pwd)/../configure-router.sh"
fi

# Require net.ipv4.ip_unprivileged_port_start=80 in /etc/sysctl.d/*.conf
# See https://github.com/containers/podman/blob/master/rootless.md

if [[ "root" == "$(id -un)" ]]; then
  SYSTEMD_SERVICE_DIR=/lib/systemd/system
else
  SYSTEMD_SERVICE_DIR="$HOME/.config/systemd/user"
  mkdir -p "$SYSTEMD_SERVICE_DIR"
fi

if [[ "$SYSTEMD_SERVICE_DIR" == "/lib/systemd/system" ]]; then
  systemctl --all | grep -F router-nginx.service >/dev/null 2>&1
  if [ $? -eq 0 ]; then
    systemctl stop router-nginx.service
    systemctl disable router-nginx.service
  fi
else
  export XDG_RUNTIME_DIR="/run/user/$UID"
  export DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR}/bus"

  # Maybe need run from host: loginctl enable-linger tools
  # see https://wiki.archlinux.org/index.php/Systemd/User
  # sudo loginctl enable-linger $RUN_USER
  systemctl --user --all | grep -F router-nginx.service >/dev/null 2>&1
  if [ $? -eq 0 ]; then
    systemctl --user stop router-nginx.service
    systemctl --user disable router-nginx.service
  fi
fi

podman container inspect router-nginx >/dev/null 2>&1

if [[ $? -eq 0 ]]; then
  podman stop router-nginx
  podman rm -f router-nginx
fi

if [[ "x$NGINX_UPDATE" != "x" ]] || [[ "x$ROUTER_IMAGE_UPDATE" != "x" ]]; then
  podman image inspect docker.io/nginx:latest >/dev/null 2>&1
  if [[ $? -eq 0 ]]; then
    podman image rm -f docker.io/nginx:latest
  fi
fi

podman pull docker.io/nginx:latest

mkdir -p "$ROUTER_LOG_ROOT_DIR/nginx"
mkdir -p "$SAMBA_DATA_DIR/download"

podman run -d --name router-nginx --security-opt label=disable \
  --mount type=bind,source=$ROUTER_HOME/etc/nginx/nginx.conf,target=/etc/nginx/nginx.conf,ro=true \
  --mount type=bind,source=$ROUTER_HOME/etc/nginx/conf.d,target=/etc/nginx/conf.d,ro=true \
  --mount type=bind,source=$ROUTER_HOME/etc/nginx/dhparam.pem,target=/etc/nginx/dhparam.pem,ro=true \
  --mount type=bind,source=$ACMESH_SSL_DIR,target=/etc/nginx/ssl,ro=true \
  --mount type=bind,source=$ROUTER_LOG_ROOT_DIR/nginx,target=/var/log/nginx \
  --mount type=bind,source=$SAMBA_DATA_DIR/download,target=/usr/share/nginx/html/downloads \
  --network=host docker.io/nginx:latest nginx -c /etc/nginx/nginx.conf

podman generate systemd router-nginx | tee -p "$SYSTEMD_SERVICE_DIR/router-nginx.service"
podman container stop router-nginx

if [[ "$SYSTEMD_SERVICE_DIR" == "/lib/systemd/system" ]]; then
  systemctl enable router-nginx.service
  systemctl daemon-reload
  systemctl start router-nginx.service
else
  systemctl --user enable "$SYSTEMD_SERVICE_DIR/router-nginx.service"
  systemctl --user daemon-reload
  systemctl --user start router-nginx.service
fi
