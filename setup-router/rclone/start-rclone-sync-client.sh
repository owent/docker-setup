#!/bin/bash

if [[ -e "/opt/nftables/sbin" ]]; then
  export PATH=/opt/nftables/sbin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/bin/site_perl:/usr/bin/vendor_perl:/usr/bin/core_perl
else
  export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/bin/site_perl:/usr/bin/vendor_perl:/usr/bin/core_perl
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [[ "x$ROUTER_HOME" == "x" ]]; then
  source "$(cd "$(dirname "$0")" && pwd)/../configure-router.sh"
fi

if [[ "x$RCLONE_DATA_DIR" == "x" ]]; then
  if [[ ! -z "$SAMBA_DATA_DIR" ]]; then
    RCLONE_DATA_DIR="$SAMBA_DATA_DIR/rclone/onedrive"
  else
    RCLONE_DATA_DIR="$RUN_HOME/rclone/onedrive"
  fi
fi
mkdir -p "$RCLONE_DATA_DIR"

echo "============ Start to check from onedrive ... ============"

rclone --log-file $SCRIPT_DIR/rclone-sync-onedrive.log --ignore-size \
  sync --dry-run onedrive-live_com:/ $RCLONE_DATA_DIR

echo "============ Start to sync from onedrive ... ============"
rclone --log-file $SCRIPT_DIR/rclone-sync-onedrive.log --ignore-size \
  sync --progress onedrive-live_com:/ $RCLONE_DATA_DIR

if [[ $? -ne 0 ]]; then
  echo "Sync from onedrive-live_com failed"
  exit 1
fi

# rclone --log-file $SCRIPT_DIR/rclone-sync-onedrive.log --ignore-size \
#        sync --progress onedrive-r-ci_com:/ $RCLONE_DATA_DIR &
#
# rclone --log-file $SCRIPT_DIR/rclone-sync-onedrive.log --ignore-size \
#        sync --progress onedrive-x-ha_com:/ $RCLONE_DATA_DIR &
#

echo "============ Start to sync to onedrive ... ============"

for SYNC_TARGET in "onedrive-live_com" "onedrive-x-ha_com" "onedrive-r-ci_com"; do
  SYNC_NEXTCLOUD_HAS_ERROR=0
  if [[ -e "$NEXTCLOUD_DATA_DIR" ]]; then
    rclone --log-file $SCRIPT_DIR/rclone-sync-onedrive.log --ignore-size \
      sync --progress $NEXTCLOUD_DATA_DIR "$SYNC_TARGET:/Apps/nextcloud/$(basename $NEXTCLOUD_DATA_DIR)" || SYNC_NEXTCLOUD_HAS_ERROR=1
  fi
  if [[ -e "$NEXTCLOUD_ETC_DIR" ]]; then
    rclone --log-file $SCRIPT_DIR/rclone-sync-onedrive.log --ignore-size \
      sync --progress $NEXTCLOUD_ETC_DIR "$SYNC_TARGET:/Apps/nextcloud/$(basename $NEXTCLOUD_ETC_DIR)" || SYNC_NEXTCLOUD_HAS_ERROR=1
  fi
  if [[ $SYNC_NEXTCLOUD_HAS_ERROR -ne 0 ]]; then
    echo "[ERROR]: Sync to onedrive-$SYNC_TARGET failed"
    break
  fi
done

rclone --log-file $SCRIPT_DIR/rclone-sync-onedrive.log --ignore-size \
  sync --progress $RCLONE_DATA_DIR/多媒体归档 onedrive-x-ha_com:/多媒体归档

for SYNC_DIR in "多媒体归档" "Apps" "Documents" "OneNote 上传" "存档" "作品"; do
  # rclone --log-file $SCRIPT_DIR/rclone-sync-onedrive.log --ignore-size \
  #        sync --progress "$RCLONE_DATA_DIR/$SYNC_DIR" "onedrive-live_com:/$SYNC_DIR"

  rclone --log-file $SCRIPT_DIR/rclone-sync-onedrive.log --ignore-size \
    sync --progress "$RCLONE_DATA_DIR/$SYNC_DIR" "onedrive-r-ci_com:/$SYNC_DIR"

done
