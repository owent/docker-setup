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

systemctl --user --all | grep -F container-postgresql.service

if [[ $? -eq 0 ]]; then
  systemctl --user stop container-postgresql
  systemctl --user disable container-postgresql
fi

podman container inspect postgresql >/dev/null 2>&1

if [[ $? -eq 0 ]]; then
  podman stop postgresql
  podman rm -f postgresql
fi

if [[ "x$POSTGRESQL_UPDATE" != "x" ]] || [[ "x$ROUTER_IMAGE_UPDATE" != "x" ]]; then
  podman image inspect docker.io/postgres:latest >/dev/null 2>&1
  if [[ $? -eq 0 ]]; then
    podman image rm -f docker.io/postgres:latest
  fi
fi

podman pull docker.io/postgres:latest

ADMIN_TOKEN=""
if [[ -e "$POSTGRESQL_ETC_DIR/admin-token" ]]; then
  ADMIN_TOKEN=$(cat "$POSTGRESQL_ETC_DIR/admin-token")
fi
if [[ "x$ADMIN_TOKEN" == "x" ]]; then
  ADMIN_TOKEN=$(openssl rand -base64 48)
  echo "$ADMIN_TOKEN" >"$POSTGRESQL_ETC_DIR/admin-token"
fi

podman run -d --name postgresql --security-opt label=disable \
  -e POSTGRES_PASSWORD=$ADMIN_TOKEN -e POSTGRES_USER=$POSTGRESQL_ADMIN_USER \
  -e PGDATA=/var/lib/postgresql/data/pgdata \
  -e POSTGRES_INITDB_WALDIR=/var/lib/postgresql/data/wal \
  --shm-size ${POSTGRESQL_SHM_SIZE}m \
  -v $POSTGRESQL_DATA_DIR:/var/lib/postgresql/data/:Z \
  -p $POSTGRESQL_PORT:5432/tcp \
  docker.io/postgres:latest -c shared_buffers=${POSTGRESQL_SHM_SIZE}MB -c max_connections=$POSTGRESQL_MAX_CONNECTIONS

podman exec postgresql ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
podman stop postgresql

podman generate systemd --name postgresql | tee $POSTGRESQL_ETC_DIR/container-postgresql.service

systemctl --user enable $POSTGRESQL_ETC_DIR/container-postgresql.service
systemctl --user restart container-postgresql
