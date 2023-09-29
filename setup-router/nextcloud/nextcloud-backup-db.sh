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

NEXTCLOUD_DB_NAME=nextcloud
NEXTCLOUD_DB_USER=nextcloud
NEXTCLOUD_DB_PASSWORD=
NEXTCLOUD_DB_HOST=127.0.0.1
NEXTCLOUD_DB_PORT=5432

if [[ "x$NEXTCLOUD_DATA_DIR" == "x" ]]; then
  NEXTCLOUD_DATA_DIR="$RUN_HOME/nextcloud/data"
fi
if [[ ! -e "$NEXTCLOUD_DATA_DIR/sql-backup" ]]; then
  mkdir -p "$NEXTCLOUD_DATA_DIR/sql-backup"
  chmod 770 -R "$NEXTCLOUD_DATA_DIR/sql-backup"
fi

BACKUP_FILE_NAME="$NEXTCLOUD_DB_NAME-sqlbkp_$(date +"%U").sql"
find . -name "$NEXTCLOUD_DB_NAME-sqlbkp_*.sql*" | xargs -r rm

podman run --rm \
  --security-opt seccomp=unconfined \
  --security-opt label=disable \
  --network=host \
  --mount type=bind,source=$PWD,target=/data/$NEXTCLOUD_DB_NAME \
  -e "PGPASSWORD=$NEXTCLOUD_DB_PASSWORD" docker.io/postgres:latest \
  pg_dump $NEXTCLOUD_DB_NAME -h $NEXTCLOUD_DB_HOST -U $NEXTCLOUD_DB_USER -p $NEXTCLOUD_DB_PORT -f /data/$NEXTCLOUD_DB_NAME/$BACKUP_FILE_NAME

tar -cvf- $BACKUP_FILE_NAME | zstd -T0 -B0 -15 --format=zstd -r -f -o $BACKUP_FILE_NAME.tar.zst -
# zstd -d --stdout $BACKUP_FILE_NAME.tar.zst | tar -xf-

if [[ $? -ne 0 ]]; then
  echo "Generate $BACKUP_FILE_NAME.tar.zst failed."
  exit 1
fi

chmod 770 "$BACKUP_FILE_NAME.tar.zst"
cp -f "$BACKUP_FILE_NAME.tar.zst" "$NEXTCLOUD_DATA_DIR/sql-backup/$BACKUP_FILE_NAME.tar.zst"
find "$NEXTCLOUD_DATA_DIR/sql-backup" -name "$NEXTCLOUD_DB_NAME-sqlbkp_*.sql*" -ctime +100 | xargs -r rm
