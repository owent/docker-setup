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
# P4D_NETWORK=(host)
# P4D_RUN_USER=root

if [[ -z "$P4D_IMAGE" ]]; then
  P4D_IMAGE="p4d"
fi
if [[ -z "$P4D_POD_NAME" ]]; then
  P4D_POD_NAME="p4d"
fi

if [[ "x$P4D_UPDATE" != "x" ]] || [[ "x$ROUTER_IMAGE_UPDATE" != "x" ]]; then
  podman rmi $P4D_IMAGE || true
  podman build -t $P4D_IMAGE -f dockerfile/p4d.Dockerfile dockerfile
  if [[ $? -ne 0 ]]; then
    echo "Build image failed"
    exit 1
  fi
else
  podman image inspect $P4D_IMAGE > /dev/null 2>&1
  if [[ $? -ne 0 ]]; then
    podman build -t $P4D_IMAGE -f dockerfile/p4d.Dockerfile dockerfile
    if [[ $? -ne 0 ]]; then
      echo "Build image failed"
      exit 1
    fi
  fi
fi

systemctl --user --all | grep -F container-$P4D_POD_NAME.service

if [[ $? -eq 0 ]]; then
  systemctl --user stop container-$P4D_POD_NAME
  systemctl --user disable container-$P4D_POD_NAME
fi

podman container inspect $P4D_POD_NAME >/dev/null 2>&1

if [[ $? -eq 0 ]]; then
  podman stop $P4D_POD_NAME
  podman rm -f $P4D_POD_NAME
fi

if [[ "x$P4D_UPDATE" != "x" ]] || [[ "x$ROUTER_IMAGE_UPDATE" != "x" ]]; then
  podman image prune -a -f --filter "until=240h"
fi

P4D_OPTIONS=(
  -e "TZ=Asia/Shanghai"
  -e "P4SSLDIR=/data/performance/ssl"
  -e "P4PORT=ssl:8666"
  -e "P4ROOT=/data/performance/root"
  -e "P4LOG=/data/archive/log/p4d.log"
  -e "P4JOURNAL=/data/archive/log/journal.log"
  --mount "type=bind,source=/data/performance/p4d,target=/data/performance"
  --mount "type=bind,source=/data/archive/p4d,target=/data/archive"
  --mount "type=bind,source=./etc/p4d,target=/etc/p4d"
  --mount "type=bind,source=/etc/timezone,target=/etc/timezone:ro"
  --mount "type=bind,source=/etc/localtime,target=/etc/localtime:ro"
  --mount "type=bind,source=/data/acme.sh/ssl/fullchain.cer,target=/data/performance/ssl/certificate.txt:ro"
  --mount "type=bind,source=/data/acme.sh/ssl/example.org.key,target=/data/performance/ssl/privatekey.txt:ro"
)

P4D_HAS_HOST_NETWORK=0
if [[ ! -z "$P4D_NETWORK" ]]; then
  for network in ${P4D_NETWORK[@]}; do
    P4D_OPTIONS+=("--network=$network")
    if [[ $network == "host" ]]; then
      P4D_HAS_HOST_NETWORK=1
    fi
  done
fi
if [[ $P4D_HAS_HOST_NETWORK -eq 0 ]]; then
  if [[ ! -z "$P4D_PORT" ]]; then
    for bing_port in ${P4D_PORT[@]}; do
      P4D_OPTIONS+=(-p "$bing_port")
    done
  fi
fi

if [[ ! -z "$P4D_RUN_USER" ]]; then
  P4D_OPTIONS+=("--user=$P4D_RUN_USER")
fi

podman run -d --name $P4D_POD_NAME --security-opt label=disable \
  "${P4D_OPTIONS[@]}" \
  $P4D_IMAGE \

if [[ $? -ne 0 ]]; then
  echo "Error: Unable to start $P4D_POD_NAME container"
  exit 1
fi

podman stop $P4D_POD_NAME

podman generate systemd --name $P4D_POD_NAME | tee $SCRIPT_DIR/container-$P4D_POD_NAME.service

systemctl --user enable $SCRIPT_DIR/container-$P4D_POD_NAME.service
systemctl --user restart container-$P4D_POD_NAME
