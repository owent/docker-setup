#!/bin/bash

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
if [[ -e "$(dirname "$SCRIPT_DIR")/configure-router.sh" ]]; then
  source "$(dirname "$SCRIPT_DIR")/configure-router.sh"
fi

export XDG_RUNTIME_DIR="/run/user/$UID"
export DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR}/bus"

# GITEA_NETWORK=(internal-backend)
# GITEA_PUBLISH=(3221:3000 6022:2222)

if [[ -z "$GITEA_IMAGE" ]]; then
  GITEA_IMAGE="local-gitea"
fi
if [[ -z "$GITEA_POD_NAME" ]]; then
  GITEA_POD_NAME="gitea"
fi

if [[ -z "$GITEA_DATA_DIR" ]]; then
  GITEA_DATA_DIR="$SCRIPT_DIR/data"
fi

if [[ -z "$GITEA_ETC_DIR" ]]; then
  GITEA_ETC_DIR="$SCRIPT_DIR/etc"
fi
mkdir -p "$GITEA_ETC_DIR"

if [[ "x$GITEA_UPDATE" != "x" ]] || [[ "x$ROUTER_IMAGE_UPDATE" != "x" ]]; then
  podman rmi $GITEA_IMAGE || true
  podman build -t $GITEA_IMAGE -f dockerfile/gitea.Dockerfile dockerfile
  if [[ $? -ne 0 ]]; then
    echo "Build image failed"
    exit 1
  fi
else
  podman image inspect $GITEA_IMAGE > /dev/null 2>&1
  if [[ $? -ne 0 ]]; then
    podman build -t $GITEA_IMAGE -f dockerfile/gitea.Dockerfile dockerfile
    if [[ $? -ne 0 ]]; then
      echo "Build image failed"
      exit 1
    fi
  fi
fi

SYSTEMD_SERVICE_DIR="$HOME/.config/systemd/user"
SYSTEMD_CONTAINER_DIR="$HOME/.config/containers/systemd"
mkdir -p "$SYSTEMD_SERVICE_DIR"
mkdir -p "$SYSTEMD_CONTAINER_DIR"

systemctl --user --all | grep -F $GITEA_POD_NAME

if [[ $? -eq 0 ]]; then
  systemctl --user stop $GITEA_POD_NAME
  systemctl --user disable $GITEA_POD_NAME
fi

podman container inspect $GITEA_POD_NAME >/dev/null 2>&1

if [[ $? -eq 0 ]]; then
  podman stop $GITEA_POD_NAME
  podman rm -f $GITEA_POD_NAME
fi

if [[ "x$GITEA_UPDATE" != "x" ]] || [[ "x$ROUTER_IMAGE_UPDATE" != "x" ]]; then
  podman image prune -a -f --filter "until=240h"
fi

GITEA_OPTIONS=(
  -e "TZ=Asia/Shanghai"
  -e "USER_UID=1000"
  -e "USER_GID=0"
  --mount "type=bind,source=$GITEA_DATA_DIR,target=/data"
  --mount "type=bind,source=$GITEA_ETC_DIR,target=/etc/gitea"
  --mount "type=bind,source=/etc/timezone,target=/etc/timezone:ro"
  --mount "type=bind,source=/etc/localtime,target=/etc/localtime:ro"
)

if [[ ! -z "$GITEA_NETWORK" ]]; then
  GITEA_HAS_HOST_NETWORK=0
  for network in ${GITEA_NETWORK[@]}; do
    GITEA_OPTIONS+=("--network=$network")
    if [[ "$network" == "host" ]]; then
      GITEA_HAS_HOST_NETWORK=1
    fi
  done
  if [[ ! -z "$GITEA_PUBLISH" ]] && [[ $GITEA_HAS_HOST_NETWORK -eq 0 ]]; then
    for publish in ${GITEA_PUBLISH[@]}; do
      GITEA_OPTIONS+=(-p "$publish")
    done
  fi
else
  GITEA_OPTIONS+=(--network=host)
fi

PODLET_IMAGE_URL="ghcr.io/containers/podlet:latest"
PODLET_RUN=($(which podlet 2>/dev/null))
FIND_PODLET_RESULT=$?
if [[ $FIND_PODLET_RESULT -ne 0 ]]; then
  (podman image inspect "$PODLET_IMAGE_URL" > /dev/null 2>&1 || podman pull "$PODLET_IMAGE_URL") && FIND_PODLET_RESULT=0 && PODLET_RUN=(podman run --rm "$PODLET_IMAGE_URL")
fi

if [[ $FIND_PODLET_RESULT -eq 0 ]]; then
  PODLET_OPTIONS=(--install --wanted-by default.target --wants network-online.target --after network-online.target)
  for network in ${GITEA_NETWORK[@]}; do
    if [[ -e "$HOME/.config/containers/systemd/$network.network" ]]; then
      PODLET_OPTIONS+=(--after "$network-network.service" --wants "$network-network.service")
    fi
  done
  ${PODLET_RUN[@]} "${PODLET_OPTIONS[@]}" \
    podman run --name $GITEA_POD_NAME --security-opt label=disable \
    "${GITEA_OPTIONS[@]}" $GITEA_IMAGE \
      | tee -p "$SYSTEMD_CONTAINER_DIR/$GITEA_POD_NAME.container"
  
else
  podman run --name $GITEA_POD_NAME --security-opt label=disable \
    "${GITEA_OPTIONS[@]}" \
    $GITEA_IMAGE \

  if [[ $? -ne 0 ]]; then
    echo "Error: Unable to start $GITEA_POD_NAME container"
    exit 1
  fi
  
  podman generate systemd --name $GITEA_POD_NAME | tee $SYSTEMD_SERVICE_DIR/$GITEA_POD_NAME.service
  podman stop $GITEA_POD_NAME
fi


if [[ "$SYSTEMD_SERVICE_DIR" == "/lib/systemd/system" ]]; then
  systemctl daemon-reload
else
  systemctl --user daemon-reload
fi

if [[ "$SYSTEMD_SERVICE_DIR" == "/lib/systemd/system" ]]; then
  if [[ $FIND_PODLET_RESULT -ne 0 ]]; then
    systemctl enable $GITEA_POD_NAME
  fi
  systemctl start $GITEA_POD_NAME
else
  if [[ $FIND_PODLET_RESULT -ne 0 ]]; then
    systemctl --user enable $GITEA_POD_NAME
  fi
  systemctl --user start $GITEA_POD_NAME
fi

if [[ "x$GITEA_UPDATE" != "x" ]] || [[ "x$ROUTER_IMAGE_UPDATE" != "x" ]]; then
  podman image prune -a -f --filter "until=240h"
fi
