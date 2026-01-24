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

if [[ -z "$RUN_HOME" ]]; then
  RUN_HOME="$HOME"
fi

if [[ -z "$POSTGRESQL_PORT" ]]; then
  POSTGRESQL_PORT=5432
fi
#POSTGRESQL_NETWORK=(internal-backend)
#POSTGRESQL_PUBLISH=($POSTGRESQL_PORT:5432/tcp)
if [[ -z "$POSTGRESQL_ETC_DIR" ]]; then
  POSTGRESQL_ETC_DIR="$RUN_HOME/postgresql/etc"
fi
mkdir -p "$POSTGRESQL_ETC_DIR"

if [[ -z "$POSTGRESQL_ADMIN_USER" ]]; then
  POSTGRESQL_ADMIN_USER=owent
fi

if [[ -z "$POSTGRESQL_SHM_SIZE" ]]; then
  POSTGRESQL_SHM_SIZE=256
fi

if [[ -z "$POSTGRESQL_EFFECTIVE_CACHE_SIZE" ]]; then
  POSTGRESQL_EFFECTIVE_CACHE_SIZE=512
fi

if [[ -z "$POSTGRESQL_WORK_MEM" ]]; then
  POSTGRESQL_WORK_MEM=16
fi

if [[ -z "$POSTGRESQL_MAINTENANCE_WORK_MEM" ]]; then
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

if [[ -z "$POSTGRESQL_FSYNC" ]]; then
  POSTGRESQL_FSYNC=off
fi

if [[ -z "$POSTGRESQL_RANDOM_PAGE_COST" ]]; then
  # 1.1 for SSD, 4 for HDD
  POSTGRESQL_RANDOM_PAGE_COST=1.1
fi

if [[ -z "$POSTGRESQL_MAX_CONNECTIONS" ]]; then
  POSTGRESQL_MAX_CONNECTIONS=256
fi

if [[ -z "$POSTGRESQL_IMAGE" ]]; then
  POSTGRESQL_IMAGE="docker.io/postgres:latest"
  # POSTGRESQL_IMAGE="docker.io/pgvector/pgvector:pg18"
fi

if [[ -z "$POSTGRESQL_DATA_DIR" ]]; then
  POSTGRESQL_DATA_DIR="$HOME/postgresql/data"
fi
mkdir -p "$POSTGRESQL_DATA_DIR"

if [[ -z "$POSTGRESQL_LOG_DIR" ]]; then
  POSTGRESQL_LOG_DIR="$HOME/postgresql/log"
fi
mkdir -p "$POSTGRESQL_LOG_DIR"

if [[ -n "$POSTGRESQL_UPDATE" ]] || [[ -n "$ROUTER_IMAGE_UPDATE" ]]; then
  podman pull $POSTGRESQL_IMAGE
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

ADMIN_TOKEN=""
if [[ -e "$POSTGRESQL_ETC_DIR/admin-token" ]]; then
  ADMIN_TOKEN=$(cat "$POSTGRESQL_ETC_DIR/admin-token")
fi
if [[ "x$ADMIN_TOKEN" == "x" ]]; then
  ADMIN_TOKEN=$(head -c 18 /dev/urandom | base64)
  echo "$ADMIN_TOKEN" >"$POSTGRESQL_ETC_DIR/admin-token"
fi

POSTGRES_OPTIONS=(
  -e POSTGRES_PASSWORD=$ADMIN_TOKEN -e POSTGRES_USER=$POSTGRESQL_ADMIN_USER
  -e PGDATA=/data/postgresql/pgdata
  --shm-size ${POSTGRESQL_SHM_SIZE}m
  --mount "type=bind,source=$POSTGRESQL_DATA_DIR,target=/data/postgresql"
)

POSTGRESQL_NETWORK_HAS_HOST=0
if [[ ! -z "$POSTGRESQL_NETWORK" ]]; then
  for network in ${POSTGRESQL_NETWORK[@]}; do
    POSTGRES_OPTIONS+=("--network=$network")
    if [[ "$network" == "host" ]]; then
      POSTGRESQL_NETWORK_HAS_HOST=1
    fi
  done
  if [[ $POSTGRESQL_NETWORK_HAS_HOST -eq 0 ]] && [[ ! -z "$POSTGRESQL_PUBLISH" ]]; then
    for publish in ${POSTGRESQL_PUBLISH[@]}; do
      POSTGRES_OPTIONS+=(-p "$publish")
    done
  fi
else
  POSTGRES_OPTIONS+=(-p $POSTGRESQL_PORT:5432/tcp)
fi

podman run -d --name postgresql --security-opt label=disable \
  "${POSTGRES_OPTIONS[@]}" $POSTGRESQL_IMAGE \
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

if [[ $? -ne 0 ]] ; then
  echo "Failed to start postgresql container."
  exit 1
fi

if [[ "x$POSTGRESQL_UPDATE" != "x" ]] || [[ "x$ROUTER_IMAGE_UPDATE" != "x" ]]; then
  podman image prune -a -f --filter "until=240h"
fi

podman exec postgresql ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
podman stop postgresql

podman generate systemd --name postgresql | tee $POSTGRESQL_ETC_DIR/container-postgresql.service

systemctl --user enable $POSTGRESQL_ETC_DIR/container-postgresql.service
systemctl --user restart container-postgresql
