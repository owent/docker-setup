#!/bin/bash

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
source "$(dirname "$SCRIPT_DIR")/configure-router.sh"

if [[ "x$RCLONE_DATA_DIR" == "x" ]]; then
  if [[ ! -z "$SAMBA_DATA_DIR" ]]; then
    RCLONE_DATA_DIR="$SAMBA_DATA_DIR/rclone/onedrive"
  else
    RCLONE_DATA_DIR="$RUN_HOME/rclone/onedrive"
  fi
fi
mkdir -p "$RCLONE_DATA_DIR"

RCLONE_REMOTE_SOURCE=onedrive-live_com
RCLONE_REMOTE_DIR_NAMES=(Apps Documents)
RCLONE_REPLICATE_TARGET=(onedrive-live_com onedrive-x-ha_com onedrive-r-ci_com)

# Truncate the log file
if [[ -e rclone-sync-onedrive.log ]]; then
  if [[ $(stat -c %s rclone-sync-onedrive.log) -gt 12582912 ]]; then # 12582912 = 12MB
    tail -c 8m rclone-sync-onedrive.log >rclone-sync-onedrive.log.bak
    rm -f rclone-sync-onedrive.log
    mv rclone-sync-onedrive.log.bak rclone-sync-onedrive.log
  fi
fi

echo "============ Start to sync ${RCLONE_REMOTE_DIR_NAMES[@]} from onedrive ... ============"
SYNC_REMOTE_HAS_ERROR=0
for REMOTE_SYNC_DIR in ${RCLONE_REMOTE_DIR_NAMES[@]}; do
  mkdir -p "$RCLONE_DATA_DIR/$REMOTE_SYNC_DIR/"

  rclone --log-file $SCRIPT_DIR/rclone-sync-onedrive.log --ignore-size --onedrive-chunk-size 2560k \
    sync --dry-run $RCLONE_REMOTE_SOURCE:/$REMOTE_SYNC_DIR $RCLONE_DATA_DIR/$REMOTE_SYNC_DIR

  echo "============ Start to sync from onedrive ... ============"
  rclone --log-file $SCRIPT_DIR/rclone-sync-onedrive.log --ignore-size --onedrive-chunk-size 2560k \
    sync --progress $RCLONE_REMOTE_SOURCE:/$REMOTE_SYNC_DIR $RCLONE_DATA_DIR/$REMOTE_SYNC_DIR || SYNC_REMOTE_HAS_ERROR=1
done

if [[ $SYNC_REMOTE_HAS_ERROR -ne 0 ]]; then
  echo "Sync ${RCLONE_REMOTE_DIR_NAMES[@]} from $RCLONE_REMOTE_SOURCE failed"
  echo "$(date +%Y-%m-%dT%H:%M:%S) [ERROR]: Sync ${RCLONE_REMOTE_DIR_NAMES[@]} from $RCLONE_REMOTE_SOURCE failed" >"$SCRIPT_DIR/warning-sync-apps-has-error.txt"
  exit 1
fi

if [[ -e "$SCRIPT_DIR/warning-sync-apps-has-error.txt" ]]; then
  rm -f "$SCRIPT_DIR/warning-sync-apps-has-error.txt"
fi

echo "============ Start to sync nextcloud to onedrive ... ============"

for SYNC_TARGET in ${RCLONE_REPLICATE_TARGET[@]}; do
  SYNC_NEXTCLOUD_HAS_ERROR=0
  if [[ -e "$NEXTCLOUD_DATA_DIR" ]]; then
    for DATA_FILTER_DIR in $(find "$NEXTCLOUD_DATA_DIR" -mindepth 1 -maxdepth 1 -name "appdata_*" -prune -o -name "*.log" -prune -o -print); do
      rclone --log-file $SCRIPT_DIR/rclone-sync-onedrive.log --ignore-size --onedrive-chunk-size 2560k \
        sync --progress "$DATA_FILTER_DIR" "$SYNC_TARGET:/Archive/nextcloud/$(basename $NEXTCLOUD_DATA_DIR)/$(basename $DATA_FILTER_DIR)" || SYNC_NEXTCLOUD_HAS_ERROR=1
    done
  fi
  if [[ -e "$NEXTCLOUD_ETC_DIR" ]]; then
    rclone --log-file $SCRIPT_DIR/rclone-sync-onedrive.log --ignore-size --onedrive-chunk-size 2560k \
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
      rclone --log-file $SCRIPT_DIR/rclone-sync-onedrive.log --ignore-size --onedrive-chunk-size 2560k \
        sync --progress $RCLONE_DATA_DIR/$REMOTE_SYNC_DIR $SYNC_TARGET:/$REMOTE_SYNC_DIR || SYNC_REMOTE_HAS_ERROR=1
      if [[ $SYNC_REMOTE_HAS_ERROR -ne 0 ]]; then
        echo "$(date +%Y-%m-%dT%H:%M:%S) [ERROR]: Sync $RCLONE_DATA_DIR/$REMOTE_SYNC_DIR to $SYNC_TARGET failed" >>"$SCRIPT_DIR/warning-sync-apps-has-error.txt"
      fi
    done
  fi
done
