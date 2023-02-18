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

if [[ "x$ONLYOFFICE_LISTEN_PORT" == "x" ]]; then
  ONLYOFFICE_LISTEN_PORT=6785
fi
mkdir -p "$RUN_HOME/onlyoffice"

if [[ "x$ONLYOFFICE_DATA_DIR" == "x" ]]; then
  ONLYOFFICE_DATA_DIR="$RUN_HOME/onlyoffice/data"
fi
if [[ ! -e "$ONLYOFFICE_DATA_DIR" ]]; then
  mkdir -p "$ONLYOFFICE_DATA_DIR"
  chmod 770 -R "$ONLYOFFICE_DATA_DIR"
fi

if [[ "x$ONLYOFFICE_CACHE_DIR" == "x" ]]; then
  ONLYOFFICE_CACHE_DIR="$RUN_HOME/onlyoffice/cache"
fi
mkdir -p "$ONLYOFFICE_CACHE_DIR"

if [[ "x$ONLYOFFICE_DB_DIR" == "x" ]]; then
  ONLYOFFICE_DB_DIR="$RUN_HOME/onlyoffice/db"
fi
mkdir -p "$ONLYOFFICE_DB_DIR"

if [[ "x$ONLYOFFICE_LOG_DIR" == "x" ]]; then
  ONLYOFFICE_LOG_DIR="$RUN_HOME/onlyoffice/log"
fi
mkdir -p "$ONLYOFFICE_LOG_DIR"

if [[ -z "$ONLYOFFICE_IMAGE_NAME" ]]; then
  ONLYOFFICE_IMAGE_NAME="documentserver"
  # Home or enterprise
  # ONLYOFFICE_IMAGE_NAME="documentserver-ee"
  # Developer
  # ONLYOFFICE_IMAGE_NAME="documentserver-de"
fi

if [[ "x$ONLYOFFICE_UPDATE" != "x" ]] || [[ "x$ROUTER_IMAGE_UPDATE" != "x" ]]; then
  podman pull "docker.io/onlyoffice/$ONLYOFFICE_IMAGE_NAME"
fi

systemctl --user --all | grep -F container-onlyoffice.service

if [[ $? -eq 0 ]]; then
  systemctl --user stop container-onlyoffice
  systemctl --user disable container-onlyoffice
fi

podman container exists onlyoffice

if [[ $? -eq 0 ]]; then
  podman stop onlyoffice
  podman rm -f onlyoffice
fi

if [[ "x$ONLYOFFICE_UPDATE" != "x" ]] || [[ "x$ROUTER_IMAGE_UPDATE" != "x" ]]; then
  podman image prune -a -f --filter "until=240h"
fi

if [[ -z "$ONLYOFFICE_JWT_SECRET" ]]; then
  if [[ -e "$RUN_HOME/onlyoffice/jwt_secret" ]]; then
    ONLYOFFICE_JWT_SECRET="$(cat "$RUN_HOME/onlyoffice/jwt_secret")"
  fi
  if [[ -z "$ONLYOFFICE_JWT_SECRET" ]]; then
    ONLYOFFICE_JWT_SECRET=$(openssl rand -base64 32)
    echo "$ONLYOFFICE_JWT_SECRET" | tee "$RUN_HOME/onlyoffice/jwt_secret"
  fi
fi

ONLYOFFICE_ENVS=(
  -e "TZ=Asia/Shanghai" -e JWT_SECRET="$ONLYOFFICE_JWT_SECRET"
  -e NGINX_WORKER_PROCESSES=12 -e NGINX_WORKER_CONNECTIONS=2048
)
if [[ ! -z "$ONLYOFFICE_DB_USER" ]] && [[ ! -z "$ONLYOFFICE_DB_PASSWD" ]] \
  && [[ ! -z "$ONLYOFFICE_DB_HOST" ]] && [[ ! -z "$ONLYOFFICE_DB_PORT" ]] \
  && [[ ! -z "$ONLYOFFICE_DB_NAME" ]] && [[ ! -z "$ONLYOFFICE_DB_TYPE" ]]; then
  ONLYOFFICE_ENVS=(${ONLYOFFICE_ENVS[@]} -e DB_TYPE=$ONLYOFFICE_DB_TYPE
    -e DB_HOST=$ONLYOFFICE_DB_HOST -e DB_PORT=$ONLYOFFICE_DB_PORT
    -e DB_NAME=$ONLYOFFICE_DB_NAME -e DB_USER=$ONLYOFFICE_DB_USER
    -e DB_PWD=$ONLYOFFICE_DB_PASSWD)
fi

podman run -d --name onlyoffice \
  --security-opt seccomp=unconfined \
  --security-opt label=disable \
  ${ONLYOFFICE_ENVS[@]} ${ONLYOFFICE_CACHE_OPTIONS[@]} \
  --mount type=bind,source=$ONLYOFFICE_DATA_DIR,target=/var/www/onlyoffice/Data \
  --mount type=bind,source=$ONLYOFFICE_CACHE_DIR,target=/var/lib/onlyoffice \
  --mount type=bind,source=$ONLYOFFICE_DB_DIR,target=/var/lib/postgresql \
  --mount type=bind,source=$ONLYOFFICE_LOG_DIR,target=/var/log/onlyoffice \
  --mount type=tmpfs,target=/run,tmpfs-mode=1777,tmpfs-size=67108864 \
  --mount type=tmpfs,target=/run/lock,tmpfs-mode=1777,tmpfs-size=67108864 \
  --mount type=tmpfs,target=/tmp,tmpfs-mode=1777 \
  --mount type=tmpfs,target=/var/log/journal,tmpfs-mode=1777 \
  -p $ONLYOFFICE_LISTEN_PORT:80 \
  docker.io/onlyoffice/$ONLYOFFICE_IMAGE_NAME
# --copy-links

podman generate systemd --name onlyoffice | tee "$RUN_HOME/onlyoffice/container-onlyoffice.service"
# podman exec onlyoffice sudo supervisorctl start ds:example
# podman exec onlyoffice sudo sed 's,autostart=false,autostart=true,' -i /etc/supervisor/conf.d/ds-example.conf
podman exec onlyoffice ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
podman exec onlyoffice sed -i 's;worker_processes[[:space:]]*1;worker_processes 8;' /etc/nginx/nginx.conf
podman exec onlyoffice sed -i '/use[[:space:]]*epoll/d' /etc/nginx/nginx.conf
podman exec onlyoffice sed -i '/events[[:space:]]*{/a use epoll;' /etc/nginx/nginx.conf

podman stop onlyoffice

systemctl --user enable "$RUN_HOME/onlyoffice/container-onlyoffice.service"
systemctl --user restart container-onlyoffice
