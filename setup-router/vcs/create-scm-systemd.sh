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

# SCM_NETWORK=(internal-backend)
SCM_RUN_USER=root

if [[ -z "$SCM_IMAGE" ]]; then
  SCM_IMAGE="local-scm-manager"
fi
if [[ -z "$SCM_POD_NAME" ]]; then
  SCM_POD_NAME="scm-manager"
fi

if [[ -z "$SCM_WEBAPP_INITIALPASSWORD_FILE" ]]; then
  SCM_WEBAPP_INITIALPASSWORD_FILE="$SCRIPT_DIR/.scmmanager_initial_password.token"
fi
if [[ -e "$SCM_WEBAPP_INITIALPASSWORD_FILE" ]]; then
  SCM_WEBAPP_INITIALPASSWORD=$(cat "$SCM_WEBAPP_INITIALPASSWORD_FILE")
fi

# 初始化用户名: scmadmin
if [[ -z "$SCM_WEBAPP_INITIALPASSWORD" ]]; then
  SCM_WEBAPP_INITIALPASSWORD="$(openssl rand -base64 12)"
  echo "$SCM_WEBAPP_INITIALPASSWORD" > "$SCM_WEBAPP_INITIALPASSWORD_FILE"
fi

if [[ -z "$SCM_DATA_DIR" ]]; then
  SCM_DATA_DIR="$SCRIPT_DIR/data/scm-manager"
fi
mkdir -p "$SCM_DATA_DIR/home"
mkdir -p "$SCM_DATA_DIR/work"

if [[ -z "$SCM_ETC_DIR" ]]; then
  SCM_ETC_DIR="$SCRIPT_DIR/etc/scm-manager"
fi
mkdir -p "$SCM_ETC_DIR"

if [[ "x$SCM_UPDATE" != "x" ]] || [[ "x$ROUTER_IMAGE_UPDATE" != "x" ]]; then
  podman rmi $SCM_IMAGE || true
  podman build -t $SCM_IMAGE -f dockerfile/scmmanager.Dockerfile dockerfile
  if [[ $? -ne 0 ]]; then
    echo "Build image failed"
    exit 1
  fi
else
  podman image inspect $SCM_IMAGE > /dev/null 2>&1
  if [[ $? -ne 0 ]]; then
    podman build -t $SCM_IMAGE -f dockerfile/scmmanager.Dockerfile dockerfile
    if [[ $? -ne 0 ]]; then
      echo "Build image failed"
      exit 1
    fi
  fi
fi

SYSTEMD_SERVICE_DIR="$HOME/.config/systemd/user"
SYSTEMD_CONTAINER_DIR="$HOME/.config/containers/systemd"
mkdir -p "$SYSTEMD_SERVICE_DIR"
mkdir -p "$SYSTEMD_CONTAINER_DIR"

systemctl --user --all | grep -F $SCM_POD_NAME

if [[ $? -eq 0 ]]; then
  systemctl --user stop $SCM_POD_NAME
  systemctl --user disable $SCM_POD_NAME
fi

podman container inspect $SCM_POD_NAME >/dev/null 2>&1

if [[ $? -eq 0 ]]; then
  podman stop $SCM_POD_NAME
  podman rm -f $SCM_POD_NAME
fi

if [[ "x$SCM_UPDATE" != "x" ]] || [[ "x$ROUTER_IMAGE_UPDATE" != "x" ]]; then
  podman image prune -a -f --filter "until=240h"
fi

SCM_OPTIONS=(
  -e "TZ=Asia/Shanghai"
  -e "SCM_WEBAPP_INITIALPASSWORD=$SCM_WEBAPP_INITIALPASSWORD"
  --mount "type=bind,source=$SCM_DATA_DIR/home,target=/var/lib/scm"
  --mount "type=bind,source=$SCM_DATA_DIR/work,target=/var/cache/scm/work"
  --mount "type=bind,source=$SCM_ETC_DIR,target=/etc/scm"
  --mount "type=bind,source=/etc/timezone,target=/etc/timezone:ro"
  --mount "type=bind,source=/etc/localtime,target=/etc/localtime:ro"
)

SCM_HAS_HOST_NETWORK=0
if [[ ! -z "$SCM_NETWORK" ]]; then
  for network in ${SCM_NETWORK[@]}; do
    SCM_OPTIONS+=("--network=$network")
    if [[ $network == "host" ]]; then
      SCM_HAS_HOST_NETWORK=1
    fi
  done
fi
if [[ $SCM_HAS_HOST_NETWORK -eq 0 ]]; then
  if [[ ! -z "$SCM_PORT" ]]; then
    for bing_port in ${SCM_PORT[@]}; do
      SCM_OPTIONS+=(-p "$bing_port")
    done
  fi
fi

if [[ ! -z "$SCM_RUN_USER" ]]; then
  SCM_OPTIONS+=("--user=$SCM_RUN_USER")
fi

which podlet >/dev/null 2>&1
FIND_PODLET_RESULT=$?

if [[ $FIND_PODLET_RESULT -eq 0 ]]; then
  podlet --install --wanted-by default.target --wants network-online.target --after network-online.target \
    podman run --name $SCM_POD_NAME --security-opt label=disable \
    "${SCM_OPTIONS[@]}" $SCM_IMAGE \
      | tee -p "$SYSTEMD_CONTAINER_DIR/$SCM_POD_NAME.container"
  
  systemctl --user daemon-reload

else
  podman run --name $SCM_POD_NAME --security-opt label=disable \
    "${SCM_OPTIONS[@]}" \
    $SCM_IMAGE \

  if [[ $? -ne 0 ]]; then
    echo "Error: Unable to start $SCM_POD_NAME container"
    exit 1
  fi
  podman stop $SCM_POD_NAME
  podman generate systemd --name $SCM_POD_NAME | tee $SYSTEMD_SERVICE_DIR/$SCM_POD_NAME.service

  systemctl --user daemon-reload
  systemctl --user enable $SCM_POD_NAME
fi

systemctl --user restart $SCM_POD_NAME
