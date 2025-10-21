#!/bin/bash

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"

export XDG_RUNTIME_DIR="/run/user/$UID"
export DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR}/bus"

if [[ -z "$RUN_USER" ]]; then
  export RUN_USER=$(id -un)
fi

source "$SCRIPT_DIR/.env"

COMPOSE_CONFIGURE=docker-compose.yaml

podman-compose -f $COMPOSE_CONFIGURE pull
if [[ $? -ne 0 ]]; then
  echo "Pull $COMPOSE_CONFIGURE failed"
  exit 1
fi
podman pull $AUTHENTIK_IMAGE_BASE/ldap:${AUTHENTIK_TAG}
if [[ $? -ne 0 ]]; then
  echo "Pull $COMPOSE_CONFIGURE failed"
  exit 1
fi
podman pull $AUTHENTIK_IMAGE_BASE/proxy:${AUTHENTIK_TAG}
if [[ $? -ne 0 ]]; then
  echo "Pull $COMPOSE_CONFIGURE failed"
  exit 1
fi
podman pull $AUTHENTIK_IMAGE_BASE/rac:${AUTHENTIK_TAG}
if [[ $? -ne 0 ]]; then
  echo "Pull $COMPOSE_CONFIGURE failed"
  exit 1
fi
podman pull $AUTHENTIK_IMAGE_BASE/radius:${AUTHENTIK_TAG}
if [[ $? -ne 0 ]]; then
  echo "Pull $COMPOSE_CONFIGURE failed"
  exit 1
fi
