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

if [[ "root" == "$(id -un)" ]]; then
  SYSTEMD_SERVICE_DIR=/lib/systemd/system
  SYSTEMD_CONTAINER_DIR=/etc/containers/systemd/
  mkdir -p "$SYSTEMD_CONTAINER_DIR"
else
  SYSTEMD_SERVICE_DIR="$HOME/.config/systemd/user"
  SYSTEMD_CONTAINER_DIR="$HOME/.config/containers/systemd"
  mkdir -p "$SYSTEMD_SERVICE_DIR"
  mkdir -p "$SYSTEMD_CONTAINER_DIR"
fi

systemctl --user --all | grep -F redis.service

if [[ $? -eq 0 ]]; then
  systemctl --user stop redis
  systemctl --user disable redis
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
  if [[ -n "$REDIS_PUBLISH" ]]; then
    for publish in ${REDIS_PUBLISH[@]}; do
      REDIS_OPTIONS+=(-p "$publish")
    done
  fi
fi

PODLET_IMAGE_URL="ghcr.io/containers/podlet:latest"
PODLET_RUN=($(which podlet 2>/dev/null))
FIND_PODLET_RESULT=$?
if [[ $FIND_PODLET_RESULT -ne 0 ]]; then
  (podman image inspect "$PODLET_IMAGE_URL" > /dev/null 2>&1 || podman pull "$PODLET_IMAGE_URL") && FIND_PODLET_RESULT=0 && PODLET_RUN=(podman run --rm "$PODLET_IMAGE_URL")
fi

if [[ $FIND_PODLET_RESULT -eq 0 ]]; then
  PODLET_OPTIONS=(--install --wanted-by default.target --wants network-online.target --after network-online.target)
  for network in ${REDIS_NETWORK[@]}; do
    if [[ -e "$HOME/.config/containers/systemd/$network.network" ]]; then
      PODLET_OPTIONS+=(--after "$network-network.service" --wants "$network-network.service")
    fi
  done
  ${PODLET_RUN[@]} "${PODLET_OPTIONS[@]}" \
    podman run --name redis --security-opt label=disable \
      "${REDIS_OPTIONS[@]}" \
      local_redis \
      | tee -p "$SYSTEMD_CONTAINER_DIR/redis.container"

else
  podman run -d --name redis --security-opt label=disable \
    "${REDIS_OPTIONS[@]}" \
    local_redis

  if [[ $? -ne 0 ]]; then
    echo "Error: Unable to start redis container"
    exit 1
  fi
  podman stop redis
  podman generate systemd --name redis | tee $SYSTEMD_SERVICE_DIR/redis.service
fi

if [[ "$SYSTEMD_SERVICE_DIR" == "/lib/systemd/system" ]]; then
  systemctl daemon-reload
else
  systemctl --user daemon-reload
fi

if [[ "$SYSTEMD_SERVICE_DIR" == "/lib/systemd/system" ]]; then
  if [[ $FIND_PODLET_RESULT -ne 0 ]]; then
    systemctl enable redis.service
  fi
  systemctl start redis.service
else
  if [[ $FIND_PODLET_RESULT -ne 0 ]]; then
    systemctl --user enable redis.service
  fi
  systemctl --user start redis.service
fi

if [[ "x$REDIS_UPDATE" != "x" ]] || [[ "x$ROUTER_IMAGE_UPDATE" != "x" ]]; then
  podman image prune -a -f --filter "until=240h"
fi
