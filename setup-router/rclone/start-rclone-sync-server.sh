#!/bin/bash

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
source "$(dirname "$SCRIPT_DIR")/configure-router.sh"

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

if [[ "x$RCLONE_ETC_DIR" == "x" ]]; then
  RCLONE_ETC_DIR="$RUN_HOME/rclone/etc"
fi
mkdir -p "$RCLONE_ETC_DIR"

if [[ "x$RCLONE_DATA_DIR" == "x" ]]; then
  if [[ ! -z "$SAMBA_DATA_DIR" ]]; then
    RCLONE_DATA_DIR="$SAMBA_DATA_DIR/rclone-data"
  else
    RCLONE_DATA_DIR="$RUN_HOME/rclone/data"
  fi
fi
mkdir -p "$RCLONE_DATA_DIR"

if [[ "x$RCLONE_IMAGE" == "x" ]]; then
  RCLONE_IMAGE="docker.io/rclone/rclone:latest"
fi

if [[ "x$RCLONE_UPDATE" != "x" ]] || [[ "x$ROUTER_IMAGE_UPDATE" != "x" ]]; then
  podman image prune -f
  podman pull $RCLONE_IMAGE
  if [[ $? -ne 0 ]]; then
    exit 1
  fi
fi

# See https://rclone.org/install/
# See https://rclone.org/onedrive/

# podman run -it --network=host --security-opt seccomp=unconfined --rm    \
#     --volume $HOME/rclone/etc:/config/rclone                            \
#     --volume $HOME/rclone/data:/data:shared                             \
#     --user $(id -u):$(id -g)                                            \
#     --volume /etc/passwd:/etc/passwd:ro                                 \
#     --volume /etc/group:/etc/group:ro                                   \
#     --device /dev/fuse --cap-add SYS_ADMIN                              \
#     docker.io/rclone/rclone config

podman run --rm --security-opt seccomp=unconfined \
  --mount type=bind,source=$RCLONE_ETC_DIR,target=/config/rclone \
  --mount type=bind,source=$RCLONE_DATA_DIR,target=/data:shared \
  --mount type=bind,source=$RUN_HOME/bitwarden/data,target=/data/bitwarden/data \
  --device /dev/fuse --cap-add SYS_ADMIN --network=host \
  $RCLONE_IMAGE \
  --log-file /data/rclone-sync-onedrive.log --ignore-size --onedrive-chunk-size 2560k \
  sync --progress /data remote-onedrive:/Apps/OWenT.Home.rclone
# --copy-links
