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

DB_BACKUP_DIR_NAME="sql-backup"
DB_NAMES=()
DB_USER=owent

if [[ -z "$DB_BACKUP_COPY_TO_DIR" ]]; then
  DB_BACKUP_COPY_TO_DIR="$SCRIPT_DIR/backup"
fi

if [[ -z "$POSTGRESQL_DATA_DIR" ]]; then
  POSTGRESQL_DATA_DIR="$SCRIPT_DIR/data"
fi

DB_BACKUP_SUFFIX="sqlbkp_$(date +"%U")"

WORK_DIR="$(pwd)"
for DB_NAME in "${DB_NAMES[@]}"; do
  BACKUP_FILE_NAME="$DB_NAME-$DB_BACKUP_SUFFIX.sql"
  find "$POSTGRESQL_DATA_DIR/$DB_BACKUP_DIR_NAME" -name "$DB_NAME-sqlbkp_*.sql*" | xargs -r rm

  podman exec postgres-db bash -c \
    "if [[ -e /data/postgres-db ]]; then DB_DATA_DIR=/data/postgres-db; else DB_DATA_DIR=/var/lib/postgres-db/data; fi;
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
  cd "$(dirname "$BACKUP_FILE_PATH")"
  tar -cvf- "$(basename "$BACKUP_FILE_PATH")" | zstd -T0 -B0 -15 --format=zstd -r -f -o $BACKUP_FILE_PATH.tar.zst -
  cd "$WORK_DIR"
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
