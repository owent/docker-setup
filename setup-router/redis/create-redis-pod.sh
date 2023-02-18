#!/bin/bash

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
source "$(dirname "$SCRIPT_DIR")/configure-router.sh"

export XDG_RUNTIME_DIR="/run/user/$UID"
export DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR}/bus"

if [[ "x$RUN_USER" == "x" ]]; then
  RUN_USER=$(id -un)
fi
RUN_HOME=$(cat /etc/passwd | awk "BEGIN{FS=\":\"} \$1 == \"$RUN_USER\" { print \$6 }")

if [[ "x$RUN_HOME" == "x" ]]; then
  RUN_HOME="$HOME"
fi

if [[ "x$REDIS_PORT" == "x" ]]; then
  REDIS_PORT=6379
fi

if [[ "x$REDIS_ETC_DIR" == "x" ]]; then
  REDIS_ETC_DIR="$RUN_HOME/redis/etc"
fi
mkdir -p "$REDIS_ETC_DIR"

if [[ "x$REDIS_DATA_DIR" == "x" ]]; then
  REDIS_DATA_DIR="$HOME/redis/data"
fi
mkdir -p "$REDIS_DATA_DIR"

if [[ "x$REDIS_UPDATE" != "x" ]] || [[ "x$ROUTER_IMAGE_UPDATE" != "x" ]]; then
  podman pull docker.io/redis:latest
fi

systemctl --user --all | grep -F container-redis.service

if [[ $? -eq 0 ]]; then
  systemctl --user stop container-redis
  systemctl --user disable container-redis
fi

podman container exists redis >/dev/null 2>&1

if [[ $? -eq 0 ]]; then
  podman stop redis
  podman rm -f redis
fi

if [[ "x$REDIS_UPDATE" != "x" ]] || [[ "x$ROUTER_IMAGE_UPDATE" != "x" ]]; then
  podman image prune -a -f --filter "until=240h"
fi

echo "Rebuild docker image ..."
echo "FROM docker.io/redis:latest

LABEL maintainer \"OWenT <admin@owent.net>\"
COPY redis.conf /usr/local/etc/redis/redis.conf
RUN ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime

CMD [ \"redis-server\", \"/usr/local/etc/redis/redis.conf\" ]
" >redis.Dockerfile

podman rmi local_redis || true
podman build -t local_redis -f redis.Dockerfile

if [[ ! -z "$REDIS_PRIVATE_NETWORK_NAME" ]] && [[ ! -z "$REDIS_PRIVATE_NETWORK_IP" ]]; then
  REDIS_PRIVATE_GATEWAY_IP=$(echo $REDIS_PRIVATE_NETWORK_IP | sed -E 's;[0-9]+$;1;')
  # --dns $ROUTER_INTERNAL_IPV4/--disable-dns
  podman network exists $REDIS_PRIVATE_NETWORK_NAME \
    || podman network create --driver bridge --ipam-driver host-local \
      --dns $ROUTER_INTERNAL_IPV4 --subnet 10.85.0.0/16 \
      $REDIS_PRIVATE_NETWORK_NAME
  REDIS_NETWORK_OPTIONS=(--network=$REDIS_PRIVATE_NETWORK_NAME --ip=$REDIS_PRIVATE_NETWORK_IP)
else
  REDIS_NETWORK_OPTIONS=(-p $REDIS_PORT:6379/tcp)
fi

podman run -d --name redis --security-opt label=disable \
  --mount type=bind,source=$REDIS_DATA_DIR,target=/data \
  ${REDIS_NETWORK_OPTIONS[@]} \
  local_redis

podman stop redis

podman generate systemd --name redis | tee $REDIS_ETC_DIR/container-redis.service

systemctl --user enable $REDIS_ETC_DIR/container-redis.service
systemctl --user restart container-redis
