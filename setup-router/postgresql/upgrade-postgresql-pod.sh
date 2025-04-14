#!/bin/bash

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
source "$(dirname "$SCRIPT_DIR")/configure-router.sh"

export XDG_RUNTIME_DIR="/run/user/$UID"
export DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR}/bus"

if [[ "x$RUN_USER" == "x" ]]; then
  RUN_USER=$(id -un)
fi
RUN_HOME=$(cat /etc/passwd | awk "BEGIN{FS=\":\"} \$1 == \"$RUN_USER\" { print \$6 }")

if [[ "x$RUN_HOME" == "x" ]]; then
  RUN_HOME="$HOME"
fi

#POSTGRESQL_NETWORK=(internal-backend)
if [[ "x$POSTGRESQL_UPGRADE_FROM" == "x" ]]; then
  POSTGRESQL_UPGRADE_FROM="16"
fi
if [[ "x$POSTGRESQL_UPGRADE_TO" == "x" ]]; then
  POSTGRESQL_UPGRADE_TO="latest"
fi

if [[ "x$POSTGRESQL_ETC_DIR" == "x" ]]; then
  POSTGRESQL_ETC_DIR="$RUN_HOME/postgresql/etc"
fi
mkdir -p "$POSTGRESQL_ETC_DIR"

if [[ "x$POSTGRESQL_ADMIN_USER" == "x" ]]; then
  POSTGRESQL_ADMIN_USER=owent
fi

if [[ "x$POSTGRESQL_SHM_SIZE" == "x" ]]; then
  POSTGRESQL_SHM_SIZE=256
fi

if [[ "x$POSTGRESQL_EFFECTIVE_CACHE_SIZE" == "x" ]]; then
  POSTGRESQL_EFFECTIVE_CACHE_SIZE=512
fi

if [[ "x$POSTGRESQL_WORK_MEM" == "x" ]]; then
  POSTGRESQL_WORK_MEM=16
fi

if [[ "x$POSTGRESQL_MAINTENANCE_WORK_MEM" == "x" ]]; then
  POSTGRESQL_MAINTENANCE_WORK_MEM=64
fi

if [[ "x$POSTGRESQL_WAL_LEVEL" == "x" ]]; then
  POSTGRESQL_WAL_LEVEL=minimal
fi

if [[ "x$POSTGRESQL_FSYNC" == "x" ]]; then
  POSTGRESQL_FSYNC=off
fi

if [[ "x$POSTGRESQL_RANDOM_PAGE_COST" == "x" ]]; then
  # 1.1 for SSD, 4 for HDD
  POSTGRESQL_RANDOM_PAGE_COST=1.1
fi

if [[ "x$POSTGRESQL_MAX_CONNECTIONS" == "x" ]]; then
  POSTGRESQL_MAX_CONNECTIONS=256
fi

if [[ "x$POSTGRESQL_PORT" == "x" ]]; then
  POSTGRESQL_PORT=5432
fi

if [[ "x$POSTGRESQL_DATA_DIR" == "x" ]]; then
  POSTGRESQL_DATA_DIR="$HOME/postgresql/data"
fi
mkdir -p "$POSTGRESQL_DATA_DIR"

if [[ "x$POSTGRESQL_UPDATE" != "x" ]] || [[ "x$ROUTER_IMAGE_UPDATE" != "x" ]]; then
  podman pull docker.io/postgres:latest
fi

podman container exists postgresql-upgrade-from

if [[ $? -eq 0 ]]; then
  podman stop postgresql-upgrade-from
  podman rm -f postgresql-upgrade-from
fi

podman container exists postgresql-upgrade-to

if [[ $? -eq 0 ]]; then
  podman stop postgresql-upgrade-to
  podman rm -f postgresql-upgrade-to
fi

if [[ "x$NEXTCLOUD_UPDATE" != "x" ]] || [[ "x$ROUTER_IMAGE_UPDATE" != "x" ]]; then
  podman image prune -a -f --filter "until=240h"
fi

ADMIN_TOKEN=""
if [[ -e "$POSTGRESQL_ETC_DIR/admin-token" ]]; then
  ADMIN_TOKEN=$(cat "$POSTGRESQL_ETC_DIR/admin-token")
fi
if [[ "x$ADMIN_TOKEN" == "x" ]]; then
  ADMIN_TOKEN=$(openssl rand -base64 48)
  echo "$ADMIN_TOKEN" >"$POSTGRESQL_ETC_DIR/admin-token"
fi

for OLD_UPGRADE_DIR in "$POSTGRESQL_DATA_DIR/pgdata.upgrade.old" "$POSTGRESQL_DATA_DIR/pgdata.upgrade.new" \
  "$POSTGRESQL_DATA_DIR/wal.upgrade.old" "$POSTGRESQL_DATA_DIR/wal.upgrade.new" \
  "$POSTGRESQL_DATA_DIR/postgresql.bin.old" "$POSTGRESQL_DATA_DIR/postgresql.share.old"; do
  if [[ -e "$OLD_UPGRADE_DIR" ]]; then
    rm -rf "$OLD_UPGRADE_DIR"
  fi
done

POSTGRES_OPTIONS_OLD=(
  -e POSTGRES_PASSWORD=$ADMIN_TOKEN -e POSTGRES_USER=$POSTGRESQL_ADMIN_USER
  -e PGDATA=/var/lib/postgresql/data/pgdata.upgrade.old
  --shm-size ${POSTGRESQL_SHM_SIZE}m
  -v $POSTGRESQL_DATA_DIR:/var/lib/postgresql/data/:Z
)

POSTGRES_OPTIONS_NEW=(
  -e POSTGRES_PASSWORD=$ADMIN_TOKEN -e POSTGRES_USER=$POSTGRESQL_ADMIN_USER
  -e PGDATA=/var/lib/postgresql/data/pgdata.upgrade.new
  --shm-size ${POSTGRESQL_SHM_SIZE}m
  -v $POSTGRESQL_DATA_DIR:/var/lib/postgresql/data/:Z
)

if [[ ! -z "$POSTGRESQL_NETWORK" ]]; then
  for network in ${POSTGRESQL_NETWORK[@]}; do
    POSTGRES_OPTIONS_OLD+=("--network=$network")
    POSTGRES_OPTIONS_NEW+=("--network=$network")
  done
fi

podman run -d --name postgresql-upgrade-from --security-opt label=disable \
  "${POSTGRES_OPTIONS_OLD[@]}" \
  docker.io/postgres:$POSTGRESQL_UPGRADE_FROM \
  -c shared_buffers=${POSTGRESQL_SHM_SIZE}MB \
  -c effective_cache_size=${POSTGRESQL_EFFECTIVE_CACHE_SIZE}MB \
  -c work_mem=${POSTGRESQL_WORK_MEM}MB \
  -c maintenance_work_mem=${POSTGRESQL_MAINTENANCE_WORK_MEM}MB \
  -c max_connections=$POSTGRESQL_MAX_CONNECTIONS \
  -c random_page_cost=$POSTGRESQL_RANDOM_PAGE_COST \
  -c superuser_reserved_connections=4 \
  -c wal_level=$POSTGRESQL_WAL_LEVEL \
  -c fsync=$POSTGRESQL_FSYNC \
  -c logging_collector=on \
  -c log_min_duration_statement=1000 \
  -c track_activities=on \
  -c track_counts=on \
  -c default_statistics_target = 100

podman run -d --name postgresql-upgrade-to --security-opt label=disable \
  "${POSTGRES_OPTIONS_NEW[@]}" \
  docker.io/postgres:latest \
  -c shared_buffers=${POSTGRESQL_SHM_SIZE}MB \
  -c effective_cache_size=${POSTGRESQL_EFFECTIVE_CACHE_SIZE}MB \
  -c work_mem=${POSTGRESQL_WORK_MEM}MB \
  -c maintenance_work_mem=${POSTGRESQL_MAINTENANCE_WORK_MEM}MB \
  -c max_connections=$POSTGRESQL_MAX_CONNECTIONS \
  -c random_page_cost=$POSTGRESQL_RANDOM_PAGE_COST \
  -c superuser_reserved_connections=4 \
  -c wal_level=$POSTGRESQL_WAL_LEVEL \
  -c fsync=$POSTGRESQL_FSYNC \
  -c logging_collector=on \
  -c log_min_duration_statement=1000 \
  -c track_activities=on \
  -c track_counts=on \
  -c default_statistics_target = 100

podman exec postgresql-upgrade-from ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
podman exec postgresql-upgrade-to ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime

set -x
podman exec postgresql-upgrade-from bash -c "mkdir -p /var/lib/postgresql/data/postgresql.bin.old && cp -rfp /usr/lib/postgresql/* /var/lib/postgresql/data/postgresql.bin.old && chmod +x -R /var/lib/postgresql/data/postgresql.bin.old"
podman exec postgresql-upgrade-from bash -c 'mkdir -p /var/lib/postgresql/data/postgresql.share.old && cp -rfp /usr/share/postgresql/* /var/lib/postgresql/data/postgresql.share.old'
podman exec postgresql-upgrade-to bash -c "cp -rfp /var/lib/postgresql/data/postgresql.share.old/* /usr/share/postgresql/"

podman exec postgresql-upgrade-to bash -c "mkdir -p /tmp/upgrade_data /tmp/upgrade_run && chown postgres:postgres /tmp/upgrade_run /tmp/upgrade_data && su postgres -c \"initdb -U $POSTGRESQL_ADMIN_USER -D /tmp/upgrade_data\""
UPGRADE_SCRIPT='cd /tmp/upgrade_run; env PGDATAOLD=/var/lib/postgresql/data/pgdata/ PGBINOLD=$(dirname "$(find /var/lib/postgresql/data/postgresql.bin.old -name pg_upgrade)") PGDATANEW=/tmp/upgrade_data PGBINNEW=$(dirname "$(which pg_upgrade)")'
UPGRADE_SCRIPT="$UPGRADE_SCRIPT su postgres -c \"pg_upgrade -U $POSTGRESQL_ADMIN_USER\""
podman exec postgresql-upgrade-to bash -c "$UPGRADE_SCRIPT"

echo "Please mv date from /tmp/upgrade_data/* into /var/lib/postgresql/data/pgdata/ with user postgres"
podman exec -it postgresql-upgrade-to bash -c "su postgres -c 'cp -rf /tmp/upgrade_data/* /var/lib/postgresql/data/pgdata/'"

podman stop postgresql-upgrade-from
podman rm postgresql-upgrade-from
podman stop postgresql-upgrade-to
