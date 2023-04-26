#!/bin/bash

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
source "$(dirname "$SCRIPT_DIR")/configure-router.sh"

export XDG_RUNTIME_DIR="/run/user/$UID"
export DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR}/bus"

if [[ "x$RUN_USER" == "x" ]]; then
  RUN_USER=$(id -un)
fi
# sudo loginctl enable-linger $RUN_USER

if [[ "x$RUN_USER" == "x" ]] || [[ "x$RUN_USER" == "xroot" ]]; then
  echo -e "\033[1;32m$0 can not run with\033[0;m \033[1;31m$RUN_USER\033[0;m"
  exit 1
fi

if [[ "x$RUN_HOME" == "x" ]]; then
  RUN_HOME=$(cat /etc/passwd | awk "BEGIN{FS=\":\"} \$1 == \"$RUN_USER\" { print \$6 }")
fi

if [[ "x$RUN_HOME" == "x" ]]; then
  RUN_HOME="$HOME"
fi

NEXTCLOUD_SETTINGS=(
  -e PHP_MEMORY_LIMIT=2000M
  -e PHP_UPLOAD_LIMIT=2000M # 32bit int, must less than 2GB
)

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

if [[ "x$NEXTCLOUD_REVERSE_ROOT_DIR" != "x" ]]; then
  NEXTCLOUD_BASE_IMAGE="docker.io/nextcloud:fpm"
  NEXTCLOUD_REVERSE_PORT=9000
else
  NEXTCLOUD_BASE_IMAGE="docker.io/nextcloud:latest"
  NEXTCLOUD_REVERSE_PORT=80
fi

if [[ "x$NEXTCLOUD_UPDATE" != "x" ]] || [[ "x$ROUTER_IMAGE_UPDATE" != "x" ]]; then
  podman pull "$NEXTCLOUD_BASE_IMAGE"
fi

systemctl --user --all | grep -F container-nextcloud.service

if [[ $? -eq 0 ]]; then
  systemctl --user stop container-nextcloud
  systemctl --user disable container-nextcloud
fi

podman container exists nextcloud

if [[ $? -eq 0 ]]; then
  podman stop nextcloud
  podman rm -f nextcloud
fi

if [[ "x$NEXTCLOUD_UPDATE" != "x" ]] || [[ "x$ROUTER_IMAGE_UPDATE" != "x" ]]; then
  podman image prune -a -f --filter "until=240h"
fi

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

echo "Rebuild docker image ..."
echo "FROM $NEXTCLOUD_BASE_IMAGE

LABEL maintainer \"OWenT <admin@owent.net>\"

RUN ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime ; \\
    export DEBIAN_FRONTEND=noninteractive; \\
    usermod -g root www-data; \\
    usermod -a -G www-data www-data; \\
    chown -R www-data:root /var/www/html/config /var/www/html/data /var/www/html/custom_apps; \\
    chmod -R 770 /var/www/html/config /var/www/html/data /var/www/html/custom_apps; \\
    sed -i -r 's;#?https?://.*/debian-security/?[[:space:]];http://mirrors.tencent.com/debian-security/ ;g' /etc/apt/sources.list ; \\
    sed -i -r 's;#?https?://.*/debian/?[[:space:]];http://mirrors.tencent.com/debian/ ;g' /etc/apt/sources.list ; \\
    apt update -y && apt upgrade -y; \\
    apt install -y cron vim; \\
    crontab -l > /tmp/cronjobs.tmp 2>/dev/null ; \\
    echo '*/5 * * * * su www-data -s /bin/bash -c "/usr/local/bin/php /var/www/html/cron.php"' >> /tmp/cronjobs.tmp ; \\
    crontab /tmp/cronjobs.tmp && rm -f /tmp/cronjobs.tmp ; \\
    rm -rf /var/lib/apt/lists/*
" >nextcloud.Dockerfile

podman rmi local_nextcloud || true
podman build \
  --security-opt seccomp=unconfined \
  --security-opt label=disable \
  -v "$NEXTCLOUD_ETC_DIR:/var/www/html/config" \
  -v "$NEXTCLOUD_DATA_DIR:/var/www/html/data" \
  -v "$NEXTCLOUD_APPS_DIR:/var/www/html/custom_apps" \
  -t local_nextcloud -f nextcloud.Dockerfile

if [[ "x$NEXTCLOUD_REVERSE_ROOT_DIR" != "x" ]]; then
  podman run --name nextcloud_temporary local_nextcloud bash -c 'du -sh /usr/src/nextcloud/*'
  if [[ $? -eq 0 ]]; then
    echo "[nextcloud] Remove old static files..."
    find "$NEXTCLOUD_REVERSE_ROOT_DIR/nextcloud/" -maxdepth 1 -mindepth 1 -name "*" | xargs -r rm -rf
    echo "[nextcloud] Copy static files..."
    podman cp --overwrite nextcloud_temporary:/usr/src/nextcloud/ "$NEXTCLOUD_REVERSE_ROOT_DIR"
    [ -e "$NEXTCLOUD_REVERSE_ROOT_DIR/nextcloud/custom_apps" ] && rm -rf "$NEXTCLOUD_REVERSE_ROOT_DIR/nextcloud/custom_apps"

    # 不能删除 .php 文件,否则反向代理时nginx的try_files会检测不过
    # find "$NEXTCLOUD_REVERSE_ROOT_DIR" -name "*.php" -type f | xargs -r rm -f
  fi
  podman rm nextcloud_temporary
fi

podman run -d --name nextcloud \
  --security-opt seccomp=unconfined \
  --security-opt label=disable \
  -e NEXTCLOUD_TRUSTED_DOMAINS="$NEXTCLOUD_TRUSTED_DOMAINS" \
  -e OVERWRITEHOST=$ROUTER_DOMAIN:6443 -e OVERWRITEPROTOCOL=https \
  -e NEXTCLOUD_ADMIN_USER=$ADMIN_USENAME -e NEXTCLOUD_ADMIN_PASSWORD=$ADMIN_TOKEN \
  -e APACHE_DISABLE_REWRITE_IP=1 -e TRUSTED_PROXIES=0.0.0.0/32 \
  ${NEXTCLOUD_CACHE_OPTIONS[@]} ${NEXTCLOUD_SETTINGS[@]} \
  --mount type=bind,source=$NEXTCLOUD_ETC_DIR,target=/var/www/html/config \
  --mount type=bind,source=$NEXTCLOUD_DATA_DIR,target=/var/www/html/data \
  --mount type=bind,source=$NEXTCLOUD_APPS_DIR,target=/var/www/html/custom_apps \
  --mount type=tmpfs,target=/run,tmpfs-mode=1777,tmpfs-size=67108864 \
  --mount type=tmpfs,target=/run/lock,tmpfs-mode=1777,tmpfs-size=67108864 \
  --mount type=tmpfs,target=/tmp,tmpfs-mode=1777 \
  --mount type=tmpfs,target=/var/log/journal,tmpfs-mode=1777 \
  -p $NEXTCLOUD_LISTEN_PORT:$NEXTCLOUD_REVERSE_PORT \
  local_nextcloud
# --copy-links

podman generate systemd --name nextcloud \
  | sed "/ExecStart=/a ExecStartPost=/usr/bin/podman exec nextcloud /bin/bash /etc/init.d/cron restart" \
  | tee "$RUN_HOME/nextcloud/container-nextcloud.service"
podman exec nextcloud sed -i 's;pm.max_children[[:space:]]*=[[:space:]][0-9]*;pm.max_children = 16;g' /usr/local/etc/php-fpm.d/www.conf

podman stop nextcloud

systemctl --user enable "$RUN_HOME/nextcloud/container-nextcloud.service"
systemctl --user restart container-nextcloud
