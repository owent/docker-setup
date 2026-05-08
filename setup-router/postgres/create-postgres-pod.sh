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

if [[ -z "$POSTGRES_PORT" ]]; then
  POSTGRES_PORT=5432
fi
#POSTGRES_NETWORK=(internal-backend)
#POSTGRES_PUBLISH=($POSTGRES_PORT:5432/tcp)
if [[ -z "$POSTGRES_ETC_DIR" ]]; then
  POSTGRES_ETC_DIR="$SCRIPT_DIR/etc"
fi
mkdir -p "$POSTGRES_ETC_DIR"

if [[ -z "$POSTGRES_ADMIN_USER" ]]; then
  POSTGRES_ADMIN_USER=owent
fi

if [[ -z "$POSTGRES_SHM_SIZE" ]]; then
  POSTGRES_SHM_SIZE=256
fi

if [[ -z "$POSTGRES_EFFECTIVE_CACHE_SIZE" ]]; then
  POSTGRES_EFFECTIVE_CACHE_SIZE=512
fi

if [[ -z "$POSTGRES_WORK_MEM" ]]; then
  POSTGRES_WORK_MEM=16
fi

if [[ -z "$POSTGRES_MAINTENANCE_WORK_MEM" ]]; then
  POSTGRES_MAINTENANCE_WORK_MEM=64
fi

if [[ -z "$POSTGRES_WAL_LEVEL" ]]; then
  #POSTGRES_WAL_LEVEL=minimal
  POSTGRES_WAL_LEVEL=replica
fi

if [[ -z "$POSTGRES_MAX_WAL_SENDERS" ]]; then
  if [[ $POSTGRES_WAL_LEVEL == "logical" ]] || [[ $POSTGRES_WAL_LEVEL == "replica" ]]; then
    POSTGRES_MAX_WAL_SENDERS=8
  else
    POSTGRES_MAX_WAL_SENDERS=0
  fi
fi

if [[ -z "$POSTGRES_FSYNC" ]]; then
  POSTGRES_FSYNC=off
fi

if [[ -z "$POSTGRES_RANDOM_PAGE_COST" ]]; then
  # 1.1 for SSD, 4 for HDD
  POSTGRES_RANDOM_PAGE_COST=1.1
fi

if [[ -z "$POSTGRES_MAX_CONNECTIONS" ]]; then
  POSTGRES_MAX_CONNECTIONS=256
fi

if [[ "root" == "$(id -un)" ]]; then
  SYSTEMD_SERVICE_DIR=/lib/systemd/system
  SYSTEMD_CONTAINER_DIR=/etc/containers/systemd/
  mkdir -p "$SYSTEMD_CONTAINER_DIR"
else
  SYSTEMD_SERVICE_DIR="$HOME/.config/systemd/user"
  SYSTEMD_CONTAINER_DIR="$HOME/.config/containers/systemd"
  mkdir -p "$SYSTEMD_SERVICE_DIR"
  mkdir -p "$SYSTEMD_CONTAINER_DIR"
fi

if [[ -z "$POSTGRES_IMAGE" ]]; then
  # POSTGRES_IMAGE="postgres:latest"
  # POSTGRES_IMAGE="pgvector/pgvector:pg18"
  POSTGRES_IMAGE="paradedb/paradedb:latest-pg18"
fi

if [[ -z "$POSTGRES_DATA_DIR" ]]; then
  POSTGRES_DATA_DIR="$SCRIPT_DIR/data"
fi
mkdir -p "$POSTGRES_DATA_DIR"

if [[ -z "$POSTGRES_LOG_DIR" ]]; then
  POSTGRES_LOG_DIR="$SCRIPT_DIR/log"
fi
mkdir -p "$POSTGRES_LOG_DIR"

if [[ -n "$POSTGRES_UPDATE" ]] || [[ -n "$ROUTER_IMAGE_UPDATE" ]]; then
  podman pull $POSTGRES_IMAGE
fi

systemctl --user --all | grep -F postgres-db.service

if [[ $? -eq 0 ]]; then
  systemctl --user stop postgres-db
  systemctl --user disable postgres-db
fi

podman container exists postgres-db

if [[ $? -eq 0 ]]; then
  podman stop postgres-db
  podman rm -f postgres-db
fi

ADMIN_TOKEN=""
if [[ -e "$POSTGRES_ETC_DIR/admin-token" ]]; then
  ADMIN_TOKEN=$(cat "$POSTGRES_ETC_DIR/admin-token")
fi
if [[ "x$ADMIN_TOKEN" == "x" ]]; then
  ADMIN_TOKEN=$(head -c 18 /dev/urandom | base64)
  echo "$ADMIN_TOKEN" >"$POSTGRES_ETC_DIR/admin-token"
fi

POSTGRES_OPTIONS=(
  -e POSTGRES_PASSWORD=$ADMIN_TOKEN -e POSTGRES_USER=$POSTGRES_ADMIN_USER
  -e PGDATA=/data/postgres-db/pgdata
  --shm-size ${POSTGRES_SHM_SIZE}m
  --mount "type=bind,source=$POSTGRES_DATA_DIR,target=/data/postgres-db"
)

POSTGRES_NETWORK_HAS_HOST=0
if [[ ! -z "$POSTGRES_NETWORK" ]]; then
  for network in ${POSTGRES_NETWORK[@]}; do
    POSTGRES_OPTIONS+=("--network=$network")
    if [[ "$network" == "host" ]]; then
      POSTGRES_NETWORK_HAS_HOST=1
    fi
  done
  if [[ $POSTGRES_NETWORK_HAS_HOST -eq 0 ]] && [[ ! -z "$POSTGRES_PUBLISH" ]]; then
    for publish in ${POSTGRES_PUBLISH[@]}; do
      POSTGRES_OPTIONS+=(-p "$publish")
    done
  fi
else
  POSTGRES_OPTIONS+=(-p $POSTGRES_PORT:5432/tcp)
fi

POSTGRES_POD_ARGS=(
  -c shared_buffers=${POSTGRES_SHM_SIZE}MB
  -c effective_cache_size=${POSTGRES_EFFECTIVE_CACHE_SIZE}MB
  -c work_mem=${POSTGRES_WORK_MEM}MB
  -c maintenance_work_mem=${POSTGRES_MAINTENANCE_WORK_MEM}MB
  -c max_connections=$POSTGRES_MAX_CONNECTIONS
  -c random_page_cost=$POSTGRES_RANDOM_PAGE_COST
  -c superuser_reserved_connections=4
  -c wal_level=$POSTGRES_WAL_LEVEL
  -c max_wal_senders=$POSTGRES_MAX_WAL_SENDERS
  -c fsync=$POSTGRES_FSYNC
  -c logging_collector=on
  -c log_min_duration_statement=1000
  -c track_activities=on
  -c track_counts=on
  -c default_statistics_target=100
)

PODLET_IMAGE_URL="ghcr.io/containers/podlet:latest"
PODLET_RUN=($(which podlet 2>/dev/null))
FIND_PODLET_RESULT=$?
if [[ $FIND_PODLET_RESULT -ne 0 ]]; then
  (podman image inspect "$PODLET_IMAGE_URL" > /dev/null 2>&1 || podman pull "$PODLET_IMAGE_URL") && FIND_PODLET_RESULT=0 && PODLET_RUN=(podman run --rm "$PODLET_IMAGE_URL")
fi

if [[ $FIND_PODLET_RESULT -eq 0 ]]; then
  PODLET_OPTIONS=(--install --wanted-by default.target --wants network-online.target --after network-online.target)
  for network in ${POSTGRES_NETWORK[@]}; do
    if [[ -e "$HOME/.config/containers/systemd/$network.network" ]]; then
      PODLET_OPTIONS+=(--after "$network-network.service" --wants "$network-network.service")
    fi
  done
  ${PODLET_RUN[@]} "${PODLET_OPTIONS[@]}" \
    podman run -d --name postgres-db --security-opt label=disable \
      "${POSTGRES_OPTIONS[@]}" $POSTGRES_IMAGE -- "${POSTGRES_POD_ARGS[@]}" \
       | tee -p "$SYSTEMD_CONTAINER_DIR/postgres-db.container"
else
    podman run -d --name postgres-db --security-opt label=disable \
      "${POSTGRES_OPTIONS[@]}" $POSTGRES_IMAGE "${POSTGRES_POD_ARGS[@]}"

  if [[ $? -ne 0 ]]; then
    echo "Failed to run postgres-db"
    exit 1
  fi

  podman generate systemd postgres-db | tee -p "$SYSTEMD_SERVICE_DIR/postgres-db.service"
  podman container stop postgres-db
fi

if [[ "$SYSTEMD_SERVICE_DIR" == "/lib/systemd/system" ]]; then
  systemctl daemon-reload
else
  systemctl --user daemon-reload
fi

if [[ "$SYSTEMD_SERVICE_DIR" == "/lib/systemd/system" ]]; then
  if [[ $FIND_PODLET_RESULT -ne 0 ]]; then
    systemctl enable postgres-db.service
  fi
  systemctl start postgres-db.service
else
  if [[ $FIND_PODLET_RESULT -ne 0 ]]; then
    systemctl --user enable postgres-db.service
  fi
  systemctl --user start postgres-db.service
fi

if [[ -n "$POSTGRES_UPDATE" ]] || [[ -n "$ROUTER_IMAGE_UPDATE" ]]; then
  podman image prune -a -f --filter "until=240h"
fi
