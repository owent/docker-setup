#!/bin/bash

# $ROUTER_DATA_ROOT_DIR/vbox/create-client-pod.sh

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"

DOCKER_EXEC=$((which podman > /dev/null 2>&1 && echo podman) || (which docker > /dev/null 2>&1 && echo docker))

if [[ -z "$VBOX_ETC_DIR" ]]; then
  VBOX_ETC_DIR="$SCRIPT_DIR/etc"
fi
if [[ -z "$VBOX_DATA_DIR" ]]; then
  VBOX_DATA_DIR="$SCRIPT_DIR/data"
fi
if [[ -z "$VBOX_LOG_DIR" ]]; then
  VBOX_LOG_DIR="$SCRIPT_DIR/logs"
fi
if [[ -z "$VBOX_IMAGE_URL" ]]; then
  VBOX_IMAGE_URL="ghcr.io/owent/vbox:latest"
fi

mkdir -p "$VBOX_ETC_DIR"
mkdir -p "$VBOX_DATA_DIR"
mkdir -p "$VBOX_LOG_DIR"

$DOCKER_EXEC image inspect "$VBOX_IMAGE_URL" > /dev/null 2>&1 || VBOX_UPDATE=1
if [[ "x$VBOX_UPDATE" != "x" ]] || [[ "x$ROUTER_IMAGE_UPDATE" != "x" ]]; then
  $DOCKER_EXEC pull "$VBOX_IMAGE_URL"
  if [[ $? -ne 0 ]]; then
    exit 1
  fi
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

if [[ "$SYSTEMD_SERVICE_DIR" == "/lib/systemd/system" ]]; then
  systemctl --all | grep -F vbox-server.service >/dev/null 2>&1
  if [ $? -eq 0 ]; then
    systemctl stop vbox-server.service
    systemctl disable vbox-server.service
  fi
else
  export XDG_RUNTIME_DIR="/run/user/$UID"
  export DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR}/bus"

  # Maybe need run from host: loginctl enable-linger tools
  # see https://wiki.archlinux.org/index.php/Systemd/User
  # sudo loginctl enable-linger $RUN_USER
  systemctl --user --all | grep -F vbox-server.service >/dev/null 2>&1
  if [ $? -eq 0 ]; then
    systemctl --user stop vbox-server.service
    systemctl --user disable vbox-server.service
  fi
fi

$DOCKER_EXEC container inspect vbox-server >/dev/null 2>&1
if [[ $? -eq 0 ]]; then
  $DOCKER_EXEC stop vbox-server
  $DOCKER_EXEC rm -f vbox-server
fi

if [[ "x$VBOX_UPDATE" != "x" ]] || [[ "x$ROUTER_IMAGE_UPDATE" != "x" ]]; then
  $DOCKER_EXEC image prune -a -f --filter "until=240h"
fi

VBOX_DOCKER_OPRIONS=(
  --cap-add=NET_BIND_SERVICE
  --network=host --security-opt label=disable
  --mount type=bind,source=$VBOX_DATA_DIR,target=/var/lib/vbox
  --mount type=bind,source=$VBOX_LOG_DIR,target=/var/log/vbox
  --mount type=bind,source=$VBOX_ETC_DIR,target=/etc/vbox,ro=true
)

if [[ ! -z "$VBOX_SSL_DIR" ]]; then
  VBOX_DOCKER_OPRIONS=("${VBOX_DOCKER_OPRIONS[@]}" --mount type=bind,source=$VBOX_SSL_DIR,target=$VBOX_SSL_DIR,ro=true)
fi

PODLET_IMAGE_URL="ghcr.io/containers/podlet:latest"
PODLET_RUN=($(which podlet 2>/dev/null))
FIND_PODLET_RESULT=$?
if [[ $FIND_PODLET_RESULT -ne 0 ]]; then
  (podman image inspect "$PODLET_IMAGE_URL" > /dev/null 2>&1 || podman pull "$PODLET_IMAGE_URL") && FIND_PODLET_RESULT=0 && PODLET_RUN=(podman run --rm "$PODLET_IMAGE_URL")
fi

if [[ $FIND_PODLET_RESULT -eq 0 ]]; then
  PODLET_OPTIONS=(--install --wanted-by default.target --wants network-online.target --after network-online.target)
  for network in ${CADDY_NETWORK[@]}; do
    if [[ -e "$HOME/.config/containers/systemd/$network.network" ]]; then
      PODLET_OPTIONS+=(--after "$network-network.service" --wants "$network-network.service")
    fi
  done
  ${PODLET_RUN[@]} "${PODLET_OPTIONS[@]}" \
    $DOCKER_EXEC run -d --name vbox-server "${VBOX_DOCKER_OPRIONS[@]}" \
      "$VBOX_IMAGE_URL" -D /var/lib/vbox -C /etc/vbox/ run | \
      sed "/\\[Install/i [Service]\nExecStartPost=$(which $DOCKER_EXEC) exec vbox-server ln -f /usr/share/zoneinfo/Asia/Shanghai /etc/timezone" | \
      tee -p "$SYSTEMD_CONTAINER_DIR/vbox-server.container"
else
  $DOCKER_EXEC run -d --name vbox-server "${VBOX_DOCKER_OPRIONS[@]}" \
    "$VBOX_IMAGE_URL" -D /var/lib/vbox -C /etc/vbox/ run

  if [[ $? -ne 0 ]]; then
    echo "Failed to run vbox-server"
    exit 1
  fi

  $DOCKER_EXEC generate systemd vbox-server | \
    sed "/ExecStart=/a ExecStartPost=$(which $DOCKER_EXEC) exec vbox-server ln -f /usr/share/zoneinfo/Asia/Shanghai /etc/timezone" | \
  tee -p "$SYSTEMD_SERVICE_DIR/vbox-server.service"
  $DOCKER_EXEC container stop vbox-server
fi

if [[ "$SYSTEMD_SERVICE_DIR" == "/lib/systemd/system" ]]; then
  systemctl daemon-reload
else
  systemctl --user daemon-reload
fi

if [[ "$SYSTEMD_SERVICE_DIR" == "/lib/systemd/system" ]]; then
  if [[ $FIND_PODLET_RESULT -ne 0 ]]; then
    systemctl enable vbox-server.service
  fi
  systemctl start vbox-server.service
else
  if [[ $FIND_PODLET_RESULT -ne 0 ]]; then
    systemctl --user enable vbox-server.service
  fi
  systemctl --user start vbox-server.service
fi

if [[ "x$VBOX_UPDATE" != "x" ]] || [[ "x$ROUTER_IMAGE_UPDATE" != "x" ]]; then
  $DOCKER_EXEC image prune -a -f --filter "until=240h"
fi

if [[ -e "$SCRIPT_DIR/create-caddy-fallback-pod.sh" ]]; then
  bash "$SCRIPT_DIR/create-caddy-fallback-pod.sh"
fi
