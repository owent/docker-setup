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

RCLONE_REPLICATE_LOCAL_REPLICATE_MODE=0
# RCLONE_REPLICATE_LOCAL_REPLICATE_MODE=1
if [[ $RCLONE_REPLICATE_LOCAL_REPLICATE_MODE -eq 0 ]]; then
  if [[ "x$RCLONE_DATA_DIR" == "x" ]]; then
    if [[ ! -z "$SAMBA_DATA_DIR" ]]; then
      RCLONE_DATA_DIR="$SAMBA_DATA_DIR/rclone/onedrive"
    else
      RCLONE_DATA_DIR="$RUN_HOME/rclone/onedrive"
    fi
  fi
else
  source "$(dirname "$SCRIPT_DIR")/syncthing/configure-server.sh"
  NEXTCLOUD_APPS_DIR=$SYNCTHING_CLIENT_HOME_DIR/data/archive/nextcloud/apps
  NEXTCLOUD_DATA_DIR=$SYNCTHING_CLIENT_HOME_DIR/data/archive/nextcloud/data
  NEXTCLOUD_EXTERNAL_DIR=$SYNCTHING_CLIENT_HOME_DIR/data/archive/nextcloud/external
  NEXTCLOUD_ETC_DIR=$SYNCTHING_CLIENT_HOME_DIR/data/archive/nextcloud/etc
  RCLONE_DATA_DIR=$SYNCTHING_CLIENT_HOME_DIR/data/archive/onedrive
fi
mkdir -p "$RCLONE_DATA_DIR"

echo "NEXTCLOUD_APPS_DIR=$NEXTCLOUD_APPS_DIR"
echo "NEXTCLOUD_DATA_DIR=$NEXTCLOUD_DATA_DIR"
echo "NEXTCLOUD_EXTERNAL_DIR=$NEXTCLOUD_EXTERNAL_DIR"
echo "NEXTCLOUD_ETC_DIR=$NEXTCLOUD_ETC_DIR"
echo "RCLONE_DATA_DIR=$RCLONE_DATA_DIR"

RCLONE_REMOTE_SOURCE=onedrive-live_com
RCLONE_REMOTE_DIR_NAMES=(Apps Documents)
RCLONE_REPLICATE_TARGET=(onedrive-live_com onedrive-x-ha_com onedrive-r-ci_com)

if [[ "x$RCLONE_IMAGE" == "x" ]]; then
  RCLONE_IMAGE="docker.io/rclone/rclone:latest"
fi

if [[ "x$RCLONE_UPDATE" != "x" ]] || [[ "x$ROUTER_IMAGE_UPDATE" != "x" ]]; then
  podman image prune -a -f --filter "until=240h"
  podman pull $RCLONE_IMAGE
  if [[ $? -ne 0 ]]; then
    exit 1
  fi
fi

# Truncate the log file
if [[ -e rclone-sync-onedrive.log ]]; then
  if [[ $(stat -c %s rclone-sync-onedrive.log) -gt 12582912 ]]; then # 12582912 = 12MB
    tail -c 8m rclone-sync-onedrive.log >rclone-sync-onedrive.log.bak
    rm -f rclone-sync-onedrive.log
    mv rclone-sync-onedrive.log.bak rclone-sync-onedrive.log
  fi
fi

if [[ $RCLONE_REPLICATE_LOCAL_REPLICATE_MODE -eq 0 ]]; then
  echo "============ Start to sync ${RCLONE_REMOTE_DIR_NAMES[@]} from onedrive ... ============"
  SYNC_REMOTE_HAS_ERROR=0
  for REMOTE_SYNC_DIR in ${RCLONE_REMOTE_DIR_NAMES[@]}; do
    mkdir -p "$RCLONE_DATA_DIR/$REMOTE_SYNC_DIR/"

    echo "============ Start to sync from onedrive ... ============"
    podman run --rm --security-opt seccomp=unconfined \
      --mount type=bind,source=$RCLONE_ETC_DIR,target=/config/rclone \
      --mount type=bind,source=$RCLONE_DATA_DIR,target=/data/remote \
      --mount type=bind,source=$SCRIPT_DIR,target=/var/log/rclone \
      --device /dev/fuse --cap-add SYS_ADMIN --network=host \
      $RCLONE_IMAGE \
      --log-file /var/log/rclone/rclone-sync-onedrive.log --ignore-size --onedrive-chunk-size 2560k \
      sync --progress $RCLONE_REMOTE_SOURCE:/$REMOTE_SYNC_DIR /data/remote/$REMOTE_SYNC_DIR || SYNC_REMOTE_HAS_ERROR=1
  done

  if [[ $SYNC_REMOTE_HAS_ERROR -ne 0 ]]; then
    echo "Sync ${RCLONE_REMOTE_DIR_NAMES[@]} from $RCLONE_REMOTE_SOURCE failed"
    echo "$(date +%Y-%m-%dT%H:%M:%S) [ERROR]: Sync ${RCLONE_REMOTE_DIR_NAMES[@]} from $RCLONE_REMOTE_SOURCE failed" >"$SCRIPT_DIR/warning-sync-apps-has-error.txt"
    exit 1
  fi
fi

if [[ -e "$SCRIPT_DIR/warning-sync-apps-has-error.txt" ]]; then
  rm -f "$SCRIPT_DIR/warning-sync-apps-has-error.txt"
fi

echo "============ Start to sync nextcloud to onedrive ... ============"

for SYNC_TARGET in ${RCLONE_REPLICATE_TARGET[@]}; do
  SYNC_NEXTCLOUD_HAS_ERROR=0
  if [[ -e "$NEXTCLOUD_DATA_DIR" ]]; then
    for DATA_FILTER_DIR in $(find "$NEXTCLOUD_DATA_DIR" -mindepth 1 -maxdepth 1 -name "appdata_*" -prune -o -name "*.log" -prune -o -print); do
      podman run --rm --security-opt seccomp=unconfined \
        --mount type=bind,source=$RCLONE_ETC_DIR,target=/config/rclone \
        --mount type=bind,source=$NEXTCLOUD_DATA_DIR,target=$NEXTCLOUD_DATA_DIR \
        --mount type=bind,source=$SCRIPT_DIR,target=/var/log/rclone \
        --network=host \
        $RCLONE_IMAGE \
        --log-file /var/log/rclone/rclone-sync-onedrive.log --ignore-size --onedrive-chunk-size 2560k \
        sync --progress "$DATA_FILTER_DIR" "$SYNC_TARGET:/Archive/nextcloud/$(basename $NEXTCLOUD_DATA_DIR)/$(basename $DATA_FILTER_DIR)" || SYNC_NEXTCLOUD_HAS_ERROR=1
    done
  fi
  if [[ -e "$NEXTCLOUD_EXTERNAL_DIR" ]]; then
    podman run --rm --security-opt seccomp=unconfined \
      --mount type=bind,source=$RCLONE_ETC_DIR,target=/config/rclone \
      --mount type=bind,source=$NEXTCLOUD_EXTERNAL_DIR,target=$NEXTCLOUD_EXTERNAL_DIR \
      --mount type=bind,source=$SCRIPT_DIR,target=/var/log/rclone \
      --network=host \
      $RCLONE_IMAGE \
      --log-file /var/log/rclone/rclone-sync-onedrive.log --ignore-size --onedrive-chunk-size 2560k \
      sync --progress $NEXTCLOUD_EXTERNAL_DIR "$SYNC_TARGET:/Archive/nextcloud/$(basename $NEXTCLOUD_EXTERNAL_DIR)" || SYNC_NEXTCLOUD_HAS_ERROR=1
  fi
  if [[ -e "$NEXTCLOUD_ETC_DIR" ]]; then
    podman run --rm --security-opt seccomp=unconfined \
      --mount type=bind,source=$RCLONE_ETC_DIR,target=/config/rclone \
      --mount type=bind,source=$NEXTCLOUD_ETC_DIR,target=$NEXTCLOUD_ETC_DIR \
      --mount type=bind,source=$SCRIPT_DIR,target=/var/log/rclone \
      --network=host \
      $RCLONE_IMAGE \
      --log-file /var/log/rclone/rclone-sync-onedrive.log --ignore-size --onedrive-chunk-size 2560k \
      sync --progress $NEXTCLOUD_ETC_DIR "$SYNC_TARGET:/Archive/nextcloud/$(basename $NEXTCLOUD_ETC_DIR)" || SYNC_NEXTCLOUD_HAS_ERROR=1
  fi
  if [[ $SYNC_NEXTCLOUD_HAS_ERROR -ne 0 ]]; then
    echo "[ERROR]: Sync to onedrive-$SYNC_TARGET failed" >>$SCRIPT_DIR/rclone-sync-onedrive.log
    echo "$(date +%Y-%m-%dT%H:%M:%S) [ERROR]: Sync apps to ${RCLONE_REPLICATE_TARGET[@]} failed" >>"$SCRIPT_DIR/warning-sync-apps-has-error.txt"
  fi
done

# Sync remote datas
for SYNC_TARGET in ${RCLONE_REPLICATE_TARGET[@]}; do
  if [[ "$SYNC_TARGET" != "$RCLONE_REMOTE_SOURCE" ]]; then
    for REMOTE_SYNC_DIR in ${RCLONE_REMOTE_DIR_NAMES[@]}; do
      SYNC_REMOTE_HAS_ERROR=0
      podman run --rm --security-opt seccomp=unconfined \
        --mount type=bind,source=$RCLONE_ETC_DIR,target=/config/rclone \
        --mount type=bind,source=$RCLONE_DATA_DIR,target=$RCLONE_DATA_DIR \
        --mount type=bind,source=$SCRIPT_DIR,target=/var/log/rclone \
        --network=host \
        $RCLONE_IMAGE \
        --log-file /var/log/rclone/rclone-sync-onedrive.log --ignore-size --onedrive-chunk-size 2560k \
        sync --progress $RCLONE_DATA_DIR/$REMOTE_SYNC_DIR $SYNC_TARGET:/$REMOTE_SYNC_DIR || SYNC_REMOTE_HAS_ERROR=1
      if [[ $SYNC_REMOTE_HAS_ERROR -ne 0 ]]; then
        echo "$(date +%Y-%m-%dT%H:%M:%S) [ERROR]: Sync $RCLONE_DATA_DIR/$REMOTE_SYNC_DIR to $SYNC_TARGET failed" >>"$SCRIPT_DIR/warning-sync-apps-has-error.txt"
      fi
    done
  fi
done
