#!/bin/bash

if [[ -e "/opt/nftables/sbin" ]]; then
  export PATH=/opt/nftables/sbin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/bin/site_perl:/usr/bin/vendor_perl:/usr/bin/core_perl
else
  export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/bin/site_perl:/usr/bin/vendor_perl:/usr/bin/core_perl
fi

if [[ "x$ROUTER_HOME" == "x" ]]; then
  source "$(cd "$(dirname "$0")" && pwd)/../configure-router.sh"
fi

export XDG_RUNTIME_DIR="/run/user/$UID"
export DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR}/bus"

RUN_USER=$(id -un)
# sudo loginctl enable-linger $RUN_USER

if [[ "x$RUN_USER" == "x" ]] || [[ "x$RUN_USER" == "xroot" ]]; then
  echo -e "\033[1;32m$0 can not run with\033[0;m \033[1;31m$RUN_USER\033[0;m"
  exit 1
fi

RUN_HOME=$(cat /etc/passwd | awk "BEGIN{FS=\":\"} \$1 == \"$RUN_USER\" { print \$6 }")

if [[ "x$RUN_HOME" == "x" ]]; then
  RUN_HOME="$HOME"
fi

if [[ "x$NEXTCLOUD_LISTEN_PORT" == "x" ]]; then
  NEXTCLOUD_LISTEN_PORT=6783
fi

mkdir -p "$RUN_HOME/nextcloud"
if [[ "x$NEXTCLOUD_ETC_DIR" == "x" ]]; then
  NEXTCLOUD_ETC_DIR="$RUN_HOME/nextcloud/etc"
fi
mkdir -p "$NEXTCLOUD_ETC_DIR"

if [[ "x$NEXTCLOUD_DATA_DIR" == "x" ]]; then
  NEXTCLOUD_DATA_DIR="$RUN_HOME/nextcloud/data"
fi
if [[ ! -e "$NEXTCLOUD_DATA_DIR" ]]; then
  mkdir -p "$NEXTCLOUD_DATA_DIR"
  chmod 770 -R "$NEXTCLOUD_DATA_DIR"
fi

if [[ "x$NEXTCLOUD_APPS_DIR" == "x" ]]; then
  NEXTCLOUD_APPS_DIR="$RUN_HOME/nextcloud/apps"
fi
mkdir -p "$NEXTCLOUD_APPS_DIR"

systemctl --user --all | grep -F container-nextcloud.service

if [[ $? -eq 0 ]]; then
  systemctl --user stop container-nextcloud
  systemctl --user disable container-nextcloud
fi

podman container inspect nextcloud >/dev/null 2>&1

if [[ $? -eq 0 ]]; then
  podman stop nextcloud
  podman rm -f nextcloud
fi

if [[ "x$NEXTCLOUD_UPDATE" != "x" ]] || [[ "x$ROUTER_IMAGE_UPDATE" != "x" ]]; then
  podman image inspect docker.io/nextcloud:latest >/dev/null 2>&1
  if [[ $? -eq 0 ]]; then
    podman image rm -f docker.io/nextcloud:latest
  fi
fi

podman pull docker.io/nextcloud:latest

if [[ "x" == "x$ADMIN_USENAME" ]]; then
  ADMIN_USENAME=owent
fi
if [[ "x" == "x$ADMIN_TOKEN" ]]; then
  ADMIN_TOKEN=$(openssl rand -base64 48)
fi

echo "$ADMIN_USENAME $ADMIN_TOKEN" | tee "$RUN_HOME/nextcloud/admin-access.log"

# See https://hub.docker.com/_/nextcloud/
# See https://docs.nextcloud.com/server/latest/admin_manual/configuration_server/reverse_proxy_configuration.html?highlight=proxy

# docker run -d \
#     -v nextcloud:/var/www/html \
#     -v apps:/var/www/html/custom_apps \
#     -v config:/var/www/html/config \
#     -v data:/var/www/html/data \
#     -v theme:/var/www/html/themes/<YOUR_CUSTOM_THEME> \
#     nextcloud

podman run -d --name nextcloud --security-opt seccomp=unconfined \
  -e NEXTCLOUD_TRUSTED_DOMAINS="home-router.x-ha.com local.x-ha.com 127.0.0.1 172.18.1.10" \
  -e OVERWRITEHOST=home-router.x-ha.com:6883 -e OVERWRITEPROTOCOL=https \
  -e NEXTCLOUD_ADMIN_USER=$ADMIN_USENAME -e NEXTCLOUD_ADMIN_PASSWORD=$ADMIN_TOKEN \
  -e APACHE_DISABLE_REWRITE_IP=1 -e TRUSTED_PROXIES=0.0.0.0/32 \
  --mount type=bind,source=$NEXTCLOUD_ETC_DIR,target=/var/www/html/config \
  --mount type=bind,source=$NEXTCLOUD_DATA_DIR,target=/var/www/html/data \
  --mount type=bind,source=$NEXTCLOUD_APPS_DIR,target=/var/www/html/custom_apps \
  -p $NEXTCLOUD_LISTEN_PORT:80 \
  docker.io/nextcloud:latest
# --copy-links

podman exec nextcloud ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime

podman generate systemd --name nextcloud | tee "$RUN_HOME/nextcloud/container-nextcloud.service"

systemctl --user enable "$RUN_HOME/nextcloud/container-nextcloud.service"
systemctl --user restart container-nextcloud
