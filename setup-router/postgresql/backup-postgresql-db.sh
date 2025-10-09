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

if [[ "x$RUN_HOME" == "x" ]]; then
  RUN_HOME=$(cat /etc/passwd | awk "BEGIN{FS=\":\"} \$1 == \"$RUN_USER\" { print \$6 }")
fi

if [[ "x$RUN_HOME" == "x" ]]; then
  RUN_HOME="$HOME"
fi

DB_BACKUP_DIR_NAME="sql-backup"
DB_NAMES=(affine_data)
DB_USER=owent
DB_BACKUP_COPY_TO_DIR="$HOME/rclone/data/sql-backup"

if [[ -z "$POSTGRESQL_DATA_DIR" ]]; then
  POSTGRESQL_DATA_DIR="$HOME/postgresql/data"
fi

DB_BACKUP_SUFFIX="sqlbkp_$(date +"%U")"

for DB_NAME in "${DB_NAMES[@]}"; do
  BACKUP_FILE_NAME="$DB_NAME-$DB_BACKUP_SUFFIX.sql"
  find "$POSTGRESQL_DATA_DIR/$DB_BACKUP_DIR_NAME" -name "$DB_NAME-sqlbkp_*.sql*" | xargs -r rm

  podman exec postgresql bash -c \
    "if [[ -e /data/postgresql ]]; then DB_DATA_DIR=/data/postgresql; else DB_DATA_DIR=/var/lib/postgresql/data; fi;
    mkdir -p \$DB_DATA_DIR/$DB_BACKUP_DIR_NAME;
    chmod 755 \$DB_DATA_DIR/$DB_BACKUP_DIR_NAME;
    pg_dump $DB_NAME -h localhost -p 5432 -U $DB_USER -f \$DB_DATA_DIR/$DB_BACKUP_DIR_NAME/$BACKUP_FILE_NAME"

  if [[ -e "$POSTGRESQL_DATA_DIR/$DB_BACKUP_DIR_NAME/$BACKUP_FILE_NAME" ]]; then
    BACKUP_FILE_PATH="$POSTGRESQL_DATA_DIR/$DB_BACKUP_DIR_NAME/$BACKUP_FILE_NAME"
  elif [[ -e "$POSTGRESQL_DATA_DIR/data/$DB_BACKUP_DIR_NAME/$BACKUP_FILE_NAME" ]]; then
    BACKUP_FILE_PATH="$POSTGRESQL_DATA_DIR/data/$DB_BACKUP_DIR_NAME/$BACKUP_FILE_NAME"
  else
    echo "Backup $DB_NAME to $POSTGRESQL_DATA_DIR/$DB_BACKUP_DIR_NAME failed."
    exit 1
  fi
  tar -cvf- $BACKUP_FILE_PATH | zstd -T0 -B0 -15 --format=zstd -r -f -o $BACKUP_FILE_PATH.tar.zst -
  # zstd -d --stdout $BACKUP_FILE_PATH.tar.zst | tar -xf-

  if [[ $? -ne 0 ]]; then
    echo "Generate $BACKUP_FILE_NAME.tar.zst failed."
    exit 1
  fi

  chmod 770 "$BACKUP_FILE_PATH.tar.zst"
  if [[ ! -z "$DB_BACKUP_COPY_TO_DIR" ]]; then
    mkdir -p "$DB_BACKUP_COPY_TO_DIR"
    cp -f "$BACKUP_FILE_PATH.tar.zst" "$DB_BACKUP_COPY_TO_DIR/$BACKUP_FILE_NAME.tar.zst"
    find "$DB_BACKUP_COPY_TO_DIR" -name "$DB_NAME-sqlbkp_*.sql*" -ctime +100 | xargs -r rm
  fi
done
