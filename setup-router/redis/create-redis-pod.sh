#!/bin/bash

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"

if [[ -e "$(dirname "$SCRIPT_DIR")/configure-router.sh" ]]; then
  source "$(dirname "$SCRIPT_DIR")/configure-router.sh"
fi

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
#REDIS_NETWORK=(internal-backend)
#REDIS_PUBLISH=($REDIS_PORT:6379/tcp)

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

REDIS_OPTIONS=(
  --mount type=bind,source=$REDIS_DATA_DIR,target=/data
)

REDIS_NETWORK_HAS_HOST=0
if [[ ! -z "$REDIS_NETWORK" ]]; then
  for network in ${REDIS_NETWORK[@]}; do
    REDIS_OPTIONS+=("--network=$network")
    if [[ "$network" == "host" ]]; then
      REDIS_NETWORK_HAS_HOST=1
    fi
  done
fi
if [[ $REDIS_NETWORK_HAS_HOST -eq 0 ]]; then
  if [[ -z "$REDIS_PUBLISH" ]]; then
    REDIS_OPTIONS+=(-p $REDIS_PORT:6379/tcp)
  else
    for publish in ${REDIS_PUBLISH[@]}; do
      REDIS_OPTIONS+=(-p "$publish")
    done
  fi
fi

podman run -d --name redis --security-opt label=disable \
  "${REDIS_OPTIONS[@]}" \
  local_redis

podman stop redis

podman generate systemd --name redis | tee $REDIS_ETC_DIR/container-redis.service

systemctl --user enable $REDIS_ETC_DIR/container-redis.service
systemctl --user restart container-redis
