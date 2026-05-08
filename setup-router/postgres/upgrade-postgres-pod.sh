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

#POSTGRESQL_NETWORK=(internal-backend)
if [[ "x$POSTGRESQL_UPGRADE_IMAGE_FROM" == "x" ]]; then
  POSTGRESQL_UPGRADE_IMAGE_FROM="paradedb/paradedb:latest-pg17"
fi
if [[ "x$POSTGRESQL_UPGRADE_IMAGE_TO" == "x" ]]; then
  POSTGRESQL_UPGRADE_IMAGE_TO="paradedb/paradedb:latest-pg18"
fi

if [[ "x$POSTGRESQL_ETC_DIR" == "x" ]]; then
  POSTGRESQL_ETC_DIR="$SCRIPT_DIR/etc"
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

if [[ -z "$POSTGRESQL_WAL_LEVEL" ]]; then
  #POSTGRESQL_WAL_LEVEL=minimal
  POSTGRESQL_WAL_LEVEL=replica
fi

if [[ -z "$POSTGRESQL_MAX_WAL_SENDERS" ]]; then
  if [[ $POSTGRESQL_WAL_LEVEL == "logical" ]] || [[ $POSTGRESQL_WAL_LEVEL == "replica" ]]; then
    POSTGRESQL_MAX_WAL_SENDERS=8
  else
    POSTGRESQL_MAX_WAL_SENDERS=0
  fi
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
  POSTGRESQL_DATA_DIR="$SCRIPT_DIR/data"
fi
mkdir -p "$POSTGRESQL_DATA_DIR"

podman container exists postgres-db-upgrade-from

if [[ $? -eq 0 ]]; then
  podman stop postgres-db-upgrade-from
  podman rm -f postgres-db-upgrade-from
fi

podman container exists postgres-db-upgrade-to

if [[ $? -eq 0 ]]; then
  podman stop postgres-db-upgrade-to
  podman rm -f postgres-db-upgrade-to
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
  "$POSTGRESQL_DATA_DIR/postgres-db.bin.old" "$POSTGRESQL_DATA_DIR/postgres-db.share.old" \
  "$POSTGRESQL_DATA_DIR/data/pgdata.upgrade.old" "$POSTGRESQL_DATA_DIR/data/pgdata.upgrade.new" \
  "$POSTGRESQL_DATA_DIR/data/wal.upgrade.old" "$POSTGRESQL_DATA_DIR/data/wal.upgrade.new" \
  "$POSTGRESQL_DATA_DIR/data/postgres-db.bin.old" "$POSTGRESQL_DATA_DIR/data/postgres-db.share.old"; do
  if [[ -e "$OLD_UPGRADE_DIR" ]]; then
    rm -rf "$OLD_UPGRADE_DIR"
  fi
done

POSTGRES_OPTIONS_OLD=(
  -e POSTGRES_PASSWORD=$ADMIN_TOKEN -e POSTGRES_USER=$POSTGRESQL_ADMIN_USER
  -e PGDATA=/data/postgres-db/pgdata.upgrade.old
  --shm-size ${POSTGRESQL_SHM_SIZE}m
  --mount type=bind,source=$POSTGRESQL_DATA_DIR,target=/data/postgres-db
)

POSTGRES_OPTIONS_NEW=(
  -e POSTGRES_PASSWORD=$ADMIN_TOKEN -e POSTGRES_USER=$POSTGRESQL_ADMIN_USER
  -e PGDATA=/data/postgres-db/pgdata.upgrade.new
  --shm-size ${POSTGRESQL_SHM_SIZE}m
  --mount type=bind,source=$POSTGRESQL_DATA_DIR,target=/data/postgres-db
)

if [[ ! -z "$POSTGRESQL_NETWORK" ]]; then
  for network in ${POSTGRESQL_NETWORK[@]}; do
    POSTGRES_OPTIONS_OLD+=("--network=$network")
    POSTGRES_OPTIONS_NEW+=("--network=$network")
  done
fi

podman run -d --name postgres-db-upgrade-from --security-opt label=disable \
  "${POSTGRES_OPTIONS_OLD[@]}" \
  $POSTGRESQL_UPGRADE_IMAGE_FROM \
  -c shared_buffers=${POSTGRESQL_SHM_SIZE}MB \
  -c effective_cache_size=${POSTGRESQL_EFFECTIVE_CACHE_SIZE}MB \
  -c work_mem=${POSTGRESQL_WORK_MEM}MB \
  -c maintenance_work_mem=${POSTGRESQL_MAINTENANCE_WORK_MEM}MB \
  -c max_connections=$POSTGRESQL_MAX_CONNECTIONS \
  -c random_page_cost=$POSTGRESQL_RANDOM_PAGE_COST \
  -c superuser_reserved_connections=4 \
  -c wal_level=$POSTGRESQL_WAL_LEVEL \
  -c max_wal_senders=$POSTGRESQL_MAX_WAL_SENDERS \
  -c fsync=$POSTGRESQL_FSYNC \
  -c logging_collector=on \
  -c log_min_duration_statement=1000 \
  -c track_activities=on \
  -c track_counts=on \
  -c default_statistics_target=100

podman run -d --name postgres-db-upgrade-to --security-opt label=disable \
  "${POSTGRES_OPTIONS_NEW[@]}" \
  $POSTGRESQL_UPGRADE_IMAGE_TO \
  -c shared_buffers=${POSTGRESQL_SHM_SIZE}MB \
  -c effective_cache_size=${POSTGRESQL_EFFECTIVE_CACHE_SIZE}MB \
  -c work_mem=${POSTGRESQL_WORK_MEM}MB \
  -c maintenance_work_mem=${POSTGRESQL_MAINTENANCE_WORK_MEM}MB \
  -c max_connections=$POSTGRESQL_MAX_CONNECTIONS \
  -c random_page_cost=$POSTGRESQL_RANDOM_PAGE_COST \
  -c superuser_reserved_connections=4 \
  -c wal_level=$POSTGRESQL_WAL_LEVEL \
  -c max_wal_senders=$POSTGRESQL_MAX_WAL_SENDERS \
  -c fsync=$POSTGRESQL_FSYNC \
  -c logging_collector=on \
  -c log_min_duration_statement=1000 \
  -c track_activities=on \
  -c track_counts=on \
  -c default_statistics_target=100

podman exec postgres-db-upgrade-from ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
podman exec postgres-db-upgrade-to ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime

set -x
podman exec postgres-db-upgrade-from bash -c "mkdir -p /data/postgres-db/postgres-db.bin.old && cp -rfp /usr/lib/postgres-db/* /data/postgres-db/postgres-db.bin.old && chmod +x -R /data/postgresql/postgresql.bin.old"
podman exec postgres-db-upgrade-from bash -c 'mkdir -p /data/postgres-db/postgres-db.share.old && cp -rfp /usr/share/postgres-db/* /data/postgres-db/postgres-db.share.old'
podman exec postgres-db-upgrade-to bash -c "cp -rfp /data/postgres-db/postgres-db.share.old/* /usr/share/postgres-db/"

podman exec postgres-db-upgrade-to bash -c "mkdir -p /tmp/upgrade_data /tmp/upgrade_run && chown postgres:postgres /tmp/upgrade_run /tmp/upgrade_data && su postgres -c \"initdb -U $POSTGRESQL_ADMIN_USER -D /tmp/upgrade_data\""
UPGRADE_SCRIPT='cd /tmp/upgrade_run; env PGDATAOLD=/data/postgres-db/pgdata/ PGBINOLD=$(dirname "$(find /data/postgres-db/postgres-db.bin.old -name pg_upgrade)") PGDATANEW=/tmp/upgrade_data PGBINNEW=$(dirname "$(which pg_upgrade)")'
UPGRADE_SCRIPT="$UPGRADE_SCRIPT su postgres -c \"pg_upgrade -U $POSTGRESQL_ADMIN_USER\""
podman exec postgres-db-upgrade-to bash -c "$UPGRADE_SCRIPT"

echo "Please mv data from /tmp/upgrade_data/* into /data/postgres-db/pgdata/ with user postgres"
podman exec -it postgres-db-upgrade-to bash -c "if [[ -e /data/postgres-db/pgdata ]]; then mv -f /data/postgres-db/pgdata /data/postgres-db/pgdata.bak.$(date +%Y%m%d%H) ; fi"
podman exec -it postgres-db-upgrade-to bash -c "if [[ -e /data/postgres-db/pgdata ]]; then rm -rf /data/postgres-db/pgdata ; fi"
podman exec -it postgres-db-upgrade-to bash -c "mkdir -p /data/postgres-db/pgdata; chown postgres:root /data/postgres-db/pgdata"
podman exec -it postgres-db-upgrade-to bash -c "su postgres -c 'cp -rfp /tmp/upgrade_data/* /data/postgres-db/pgdata/'"

podman stop postgres-db-upgrade-from
podman rm postgres-db-upgrade-from
podman stop postgres-db-upgrade-to

# Modify pgdata/pg_hba.conf to allow remote access if needed
# host    all             all             10.0.0.0/8              trust
# host    all             all             172.16.0.0/12           trust
# host    all             all             192.168.0.0/16          trust
# host    all             all             fc00::/7                trust
# host    all             all             fe80::/16               trust