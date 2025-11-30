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

if [[ -z "$NEXTCLOUD_DOMAIN" ]]; then
  NEXTCLOUD_DOMAIN=$ROUTER_DOMAIN
fi

NEXTCLOUD_NETWORK=(internal-backend internal-frontend)
if [[ -z "$NEXTCLOUD_PHP_MEMORY_LIMIT" ]]; then
  TOTAL_MEM_KB=$(cat /proc/meminfo | grep MemTotal | grep -o -E '[0-9]+')
  if [[ ! -z "$TOTAL_MEM_KB" ]]; then
    if [[ $TOTAL_MEM_KB -lt 1048576 ]]; then
      NEXTCLOUD_PHP_MEMORY_LIMIT=512M
    elif [[ $TOTAL_MEM_KB -lt 4194304 ]]; then
      NEXTCLOUD_PHP_MEMORY_LIMIT=1024M
    elif [[ $TOTAL_MEM_KB -lt 67108864 ]]; then
      NEXTCLOUD_PHP_MEMORY_LIMIT=$(($TOTAL_MEM_KB/4096))M
    else
      NEXTCLOUD_PHP_MEMORY_LIMIT=16384M
    fi
  else
    NEXTCLOUD_PHP_MEMORY_LIMIT=2048M
  fi
fi
NEXTCLOUD_SETTINGS=(
  -e PHP_MEMORY_LIMIT=$NEXTCLOUD_PHP_MEMORY_LIMIT
  -e PHP_UPLOAD_LIMIT=2000M # 32bit int, must less than 2GB
)
if [[ ! -z "$REDIS_PRIVATE_NETWORK_NAME" ]] && [[ ! -z "$REDIS_PRIVATE_NETWORK_IP" ]]; then
  NEXTCLOUD_CACHE_OPTIONS=(--network=$REDIS_PRIVATE_NETWORK_NAME -e REDIS_HOST=$REDIS_PRIVATE_NETWORK_IP -e REDIS_HOST_PORT=$REDIS_PORT) # -e REDIS_HOST_PASSWORD=)
elif [[ ! -z "$REDIS_HOST" ]]; then
  NEXTCLOUD_CACHE_OPTIONS=(-e REDIS_HOST=$REDIS_HOST -e REDIS_HOST_PORT=$REDIS_PORT) # -e REDIS_HOST_PASSWORD=)
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

if [[ "x$NEXTCLOUD_EXTERNAL_DIR" == "x" ]]; then
  NEXTCLOUD_EXTERNAL_DIR="$RUN_HOME/nextcloud/external"
fi
if [[ ! -e "$NEXTCLOUD_EXTERNAL_DIR" ]]; then
  mkdir -p "$NEXTCLOUD_EXTERNAL_DIR"
  chmod 770 -R "$NEXTCLOUD_EXTERNAL_DIR"
fi

if [[ "x$NEXTCLOUD_TEMPORARY_DIR" == "x" ]]; then
  NEXTCLOUD_TEMPORARY_DIR="$RUN_HOME/nextcloud/temporary"
fi
if [[ ! -e "$NEXTCLOUD_TEMPORARY_DIR" ]]; then
  mkdir -p "$NEXTCLOUD_TEMPORARY_DIR"
  chmod 770 -R "$NEXTCLOUD_TEMPORARY_DIR"
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
  if [[ $? -ne 0 ]]; then
    exit 1
  fi
fi

systemctl --user enable --now podman.socket
systemctl --user start --now podman.socket
DOCKER_SOCK_PATH="$XDG_RUNTIME_DIR/podman/podman.sock"
# php occ app_api:daemon:register local_docker "Docker Local" "docker-install" "http" "/var/run/docker.sock" "http://nextcloud.local" --net=nextcloud

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

# https://github.com/nextcloud/docker/blob/master/.examples/dockerfiles/cron/fpm-alpine/Dockerfile
# https://github.com/nextcloud/docker/blob/master/.examples/dockerfiles/cron/fpm/Dockerfile
echo "FROM $NEXTCLOUD_BASE_IMAGE

LABEL maintainer \"OWenT <admin@owent.net>\"

RUN ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime ; \\
    export DEBIAN_FRONTEND=noninteractive; \\
    sed -i -r 's;https?://.*/(debian-security/?);http://mirrors.tencent.com/\1;g' /etc/apt/sources.list.d/debian.sources ; \\
    sed -i -r 's;https?://.*/(debian/?);http://mirrors.tencent.com/\1;g' /etc/apt/sources.list.d/debian.sources ; \\
    apt-get update -y && apt-get install -y supervisor && rm -rf /var/lib/apt/lists/* && mkdir /var/log/supervisord /var/run/supervisord; \\
    chmod 770 -R /var/log/supervisord /var/run/supervisord

RUN export DEBIAN_FRONTEND=noninteractive; \\
    usermod -g root www-data; \\
    usermod -a -G www-data www-data; \\
    chown -R www-data:root /var/www/html/config /var/www/html/data /var/www/html/custom_apps; \\
    chmod -R 770 /var/www/html/config /var/www/html/data /var/www/html/custom_apps; \\
    chmod -R 777 /usr/local/etc

" >nextcloud.Dockerfile

if [[ "x$NEXTCLOUD_REVERSE_ROOT_DIR" != "x" ]]; then
  echo "COPY supervisord-phpfpm.conf /supervisord.conf" >>nextcloud.Dockerfile
else
  echo "COPY supervisord-apache.conf /supervisord.conf" >>nextcloud.Dockerfile
fi

echo '
ENV NEXTCLOUD_UPDATE=1

CMD ["/usr/bin/supervisord", "-c", "/supervisord.conf"]
' >>nextcloud.Dockerfile

#     sed -i -r 's;#?https?://.*/debian-security/?[[:space:]];http://mirrors.tencent.com/debian-security/ ;g' /etc/apt/sources.list ; \\
#     sed -i -r 's;#?https?://.*/debian/?[[:space:]];http://mirrors.tencent.com/debian/ ;g' /etc/apt/sources.list ; \\
#     apt update -y && apt upgrade -y; \\
#     apt install -y cron vim; \\
#     crontab -l > /tmp/cronjobs.tmp 2>/dev/null ; \\
#     echo '*/5 * * * * su www-data -s /bin/bash -c "/usr/local/bin/php /var/www/html/cron.php"' >> /tmp/cronjobs.tmp ; \\
#     crontab /tmp/cronjobs.tmp && rm -f /tmp/cronjobs.tmp ; \\
#     rm -rf /var/lib/apt/lists/*

podman rmi local_nextcloud || true
podman build \
  --security-opt seccomp=unconfined \
  --security-opt label=disable \
  --network=host \
  -v "$NEXTCLOUD_ETC_DIR:/var/www/html/config" \
  -v "$NEXTCLOUD_DATA_DIR:/var/www/html/data" \
  -v "$NEXTCLOUD_APPS_DIR:/var/www/html/custom_apps" \
  -t local_nextcloud -f nextcloud.Dockerfile

if [[ "x$NEXTCLOUD_REVERSE_ROOT_DIR" != "x" ]]; then
  NEXTCLOUD_COPY_PATHS=($(podman run --name nextcloud_temporary local_nextcloud bash -c 'find /usr/src/nextcloud/ -maxdepth 1 -mindepth 1 -name "*"' | grep -E '^/usr/src/nextcloud/'))
  if [[ $? -eq 0 ]]; then
    echo "[nextcloud] Remove old static files..."
    for OLD_PATH in $(find "$NEXTCLOUD_REVERSE_ROOT_DIR/" -maxdepth 1 -mindepth 1 -name "*"); do
      OLD_PATH_BASENAME="$(basename "$OLD_PATH")"
      if [[ -z "$OLD_PATH_BASENAME" ]] || [[ "$OLD_PATH_BASENAME" == "." ]] || [[ "$OLD_PATH_BASENAME" == ".." ]] \
        || [[ "$OLD_PATH_BASENAME" == "custom_apps" ]]; then
        continue
      fi
      echo "[nextcloud] Remove $OLD_PATH ..."
      rm -rf "$OLD_PATH"
    done
    echo "[nextcloud] Copy static files..."
    for COPY_PATH in "${NEXTCLOUD_COPY_PATHS[@]}"; do
      COPY_PATH_BASENAME="$(basename "$COPY_PATH")"
      if [[ -z "$COPY_PATH_BASENAME" ]] || [[ "$COPY_PATH_BASENAME" == "." ]] || [[ "$COPY_PATH_BASENAME" == ".." ]] \
        || [[ "$COPY_PATH_BASENAME" == "custom_apps" ]]; then
        continue
      fi
      echo "[nextcloud] Copy $COPY_PATH_BASENAME ..."
      podman cp --overwrite nextcloud_temporary:"$COPY_PATH" "$NEXTCLOUD_REVERSE_ROOT_DIR/"
    done

    # 不能删除 .php 文件,否则反向代理时nginx的try_files会检测不过
    # find "$NEXTCLOUD_REVERSE_ROOT_DIR" -name "*.php" -type f | xargs -r rm -f
  fi
  podman rm nextcloud_temporary
fi

NEXTCLOUD_NETWORK_HAS_HOST=0
if [[ ! -z "$NEXTCLOUD_NETWORK" ]]; then
  for network in ${NEXTCLOUD_NETWORK[@]}; do
    NEXTCLOUD_SETTINGS+=("--network=$network")
    if [[ "$network" == "host" ]]; then
      NEXTCLOUD_NETWORK_HAS_HOST=1
    fi
  done
fi
if [[ $NEXTCLOUD_NETWORK_HAS_HOST -eq 0 ]]; then
  NEXTCLOUD_SETTINGS+=(-p $NEXTCLOUD_LISTEN_PORT:$NEXTCLOUD_REVERSE_PORT)
fi

podman run -d --name nextcloud \
  --security-opt seccomp=unconfined \
  --security-opt label=disable \
  -e NEXTCLOUD_TRUSTED_DOMAINS="$NEXTCLOUD_TRUSTED_DOMAINS" \
  -e OVERWRITEHOST=$NEXTCLOUD_DOMAIN:6443 -e OVERWRITEPROTOCOL=https \
  -e NEXTCLOUD_ADMIN_USER=$ADMIN_USENAME -e NEXTCLOUD_ADMIN_PASSWORD=$ADMIN_TOKEN \
  -e APACHE_DISABLE_REWRITE_IP=1 -e TRUSTED_PROXIES=0.0.0.0/32 \
  ${NEXTCLOUD_CACHE_OPTIONS[@]} ${NEXTCLOUD_SETTINGS[@]} \
  -u www-data:root \
  --mount type=bind,source=$NEXTCLOUD_ETC_DIR,target=/var/www/html/config \
  --mount type=bind,source=$NEXTCLOUD_DATA_DIR,target=/var/www/html/data \
  --mount type=bind,source=$NEXTCLOUD_APPS_DIR,target=/var/www/html/custom_apps \
  --mount type=bind,source=$NEXTCLOUD_EXTERNAL_DIR,target=/data/external \
  --mount type=bind,source=$NEXTCLOUD_TEMPORARY_DIR,target=/data/temporary \
  --mount type=bind,source=$DOCKER_SOCK_PATH,target=/var/run/docker.sock \
  --mount type=tmpfs,target=/run,tmpfs-mode=1777,tmpfs-size=67108864 \
  --mount type=tmpfs,target=/run/lock,tmpfs-mode=1777,tmpfs-size=67108864 \
  --mount type=tmpfs,target=/tmp,tmpfs-mode=1777 \
  --mount type=tmpfs,target=/var/log/journal,tmpfs-mode=1777 \
  local_nextcloud
# --copy-links

podman generate systemd --name nextcloud \
  | sed "/ExecStart=/a ExecStartPost=/usr/bin/podman exec -d nextcloud /bin/bash /cron.sh" \
  | tee "$RUN_HOME/nextcloud/container-nextcloud.service"
podman exec nextcloud sed -i 's;pm.max_children[[:space:]]*=[[:space:]][0-9]*;pm.max_children = 16;g' /usr/local/etc/php-fpm.d/www.conf
podman exec nextcloud sed -i 's;group[[:space:]]*=[[:space:]]*www-data;group = root;g' /usr/local/etc/php-fpm.d/www.conf
podman exec nextcloud bash -c 'rm -rf /var/www/html/core/skeleton/*'

podman stop nextcloud

systemctl --user enable "$RUN_HOME/nextcloud/container-nextcloud.service"
systemctl --user restart container-nextcloud
