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

if [[ "x$POSTGRESQL_MAX_WAL_SENDERS" == "x" ]]; then
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
  POSTGRESQL_DATA_DIR="$HOME/postgresql/data"
fi
mkdir -p "$POSTGRESQL_DATA_DIR"

if [[ "x$POSTGRESQL_UPDATE" != "x" ]] || [[ "x$ROUTER_IMAGE_UPDATE" != "x" ]]; then
  podman pull docker.io/postgres:latest
fi

systemctl --user --all | grep -F container-postgresql.service

if [[ $? -eq 0 ]]; then
  systemctl --user stop container-postgresql
  systemctl --user disable container-postgresql
fi

podman container exists postgresql

if [[ $? -eq 0 ]]; then
  podman stop postgresql
  podman rm -f postgresql
fi

if [[ "x$NEXTCLOUD_UPDATE" != "x" ]] || [[ "x$ROUTER_IMAGE_UPDATE" != "x" ]]; then
  podman image prune -a -f --filter "until=240h"
fi

ADMIN_TOKEN=""
if [[ -e "$POSTGRESQL_ETC_DIR/admin-token" ]]; then
  ADMIN_TOKEN=$(cat "$POSTGRESQL_ETC_DIR/admin-token")
fi
if [[ "x$ADMIN_TOKEN" == "x" ]]; then
  ADMIN_TOKEN=$(head -c 18 /dev/urandom | base64)
  echo "$ADMIN_TOKEN" >"$POSTGRESQL_ETC_DIR/admin-token"
fi

podman run -d --name postgresql --security-opt label=disable \
  -e POSTGRES_PASSWORD=$ADMIN_TOKEN -e POSTGRES_USER=$POSTGRESQL_ADMIN_USER \
  -e PGDATA=/var/lib/postgresql/data/pgdata \
  -e POSTGRES_INITDB_WALDIR=/var/lib/postgresql/data/wal \
  --shm-size ${POSTGRESQL_SHM_SIZE}m \
  -v $POSTGRESQL_DATA_DIR:/var/lib/postgresql/data/:Z \
  -p $POSTGRESQL_PORT:5432/tcp \
  docker.io/postgres:latest \
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

podman exec postgresql ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
podman stop postgresql

podman generate systemd --name postgresql | tee $POSTGRESQL_ETC_DIR/container-postgresql.service

systemctl --user enable $POSTGRESQL_ETC_DIR/container-postgresql.service
systemctl --user restart container-postgresql
