#!/bin/bash

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
source "$(dirname "$SCRIPT_DIR")/configure-router.sh"

DOCKER_EXEC=$((which podman > /dev/null 2>&1 && echo podman) || (which docker > /dev/null 2>&1 && echo docker))

if [[ -z "$VBOX_ETC_DIR" ]]; then
  VBOX_ETC_DIR="$SCRIPT_DIR/etc"
fi
if [[ -z "$VBOX_DATA_DIR" ]]; then
  VBOX_DATA_DIR="$SCRIPT_DIR/data"
fi
if [[ -z "$VBOX_LOG_DIR" ]]; then
  if [[ ! -z "$ROUTER_LOG_ROOT_DIR" ]]; then
    VBOX_LOG_DIR="$ROUTER_LOG_ROOT_DIR/vbox/logs"
  else
    VBOX_LOG_DIR="$SCRIPT_DIR/logs"
  fi
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
  systemctl --all | grep -F vbox-client.service >/dev/null 2>&1
  if [ $? -eq 0 ]; then
    systemctl stop vbox-client.service || true
    systemctl disable vbox-client.service || true
  fi
else
  export XDG_RUNTIME_DIR="/run/user/$UID"
  export DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR}/bus"

  # Maybe need run from host: loginctl enable-linger tools
  # see https://wiki.archlinux.org/index.php/Systemd/User
  # sudo loginctl enable-linger $RUN_USER
  systemctl --user --all | grep -F vbox-client.service >/dev/null 2>&1
  if [ $? -eq 0 ]; then
    systemctl --user stop vbox-client.service || true
    systemctl --user disable vbox-client.service || true
  fi
fi

$DOCKER_EXEC container inspect vbox-client >/dev/null 2>&1
if [[ $? -eq 0 ]]; then
  $DOCKER_EXEC stop vbox-client
  $DOCKER_EXEC rm -f vbox-client
fi

if [[ "x$VBOX_UPDATE" != "x" ]] || [[ "x$ROUTER_IMAGE_UPDATE" != "x" ]]; then
  $DOCKER_EXEC image prune -a -f --filter "until=240h"
fi

VBOX_DOCKER_OPRIONS=(
  --cap-add=NET_ADMIN --cap-add=NET_BIND_SERVICE
  --network=host --security-opt label=disable
  --device /dev/net/tun:/dev/net/tun
  --mount type=bind,source=$VBOX_DATA_DIR,target=/var/lib/vbox
  --mount type=bind,source=$VBOX_LOG_DIR,target=/var/log/vbox
  --mount type=bind,source=$VBOX_ETC_DIR,target=/etc/vbox,ro=true
  --mount type=bind,source=$ACMESH_SSL_DIR,target=/data/ssl,ro=true
)

if [[ -z "$ROUTER_NET_LOCAL_ENABLE_VBOX" ]] || [[ $ROUTER_NET_LOCAL_ENABLE_VBOX -eq 0 ]]; then
  bash "$SCRIPT_DIR/setup-client-pod-ip-nft.sh" clear
  bash "$SCRIPT_DIR/setup-client-pod-ip-rules.sh" configure
else
  bash "$SCRIPT_DIR/setup-client-pod-ip-rules.sh" clear
  bash "$SCRIPT_DIR/setup-client-pod-ip-nft.sh" configure
fi

PODLET_IMAGE_URL="ghcr.io/containers/podlet:latest"
PODLET_RUN=($(which podlet 2>/dev/null))
FIND_PODLET_RESULT=$?
if [[ $FIND_PODLET_RESULT -ne 0 ]]; then
  (podman image inspect "$PODLET_IMAGE_URL" > /dev/null 2>&1 || podman pull "$PODLET_IMAGE_URL") && FIND_PODLET_RESULT=0 && PODLET_RUN=(podman run --rm "$PODLET_IMAGE_URL")
fi

if [[ -z "$ROUTER_NET_LOCAL_ENABLE_VBOX" ]] || [[ $ROUTER_NET_LOCAL_ENABLE_VBOX -eq 0 ]]; then
  VBOX_CLIENT_EXEC_STOP_POST="ExecStopPost=/bin/bash $SCRIPT_DIR/setup-client-pod-whitelist-rules.sh clear"
  VBOX_CLIENT_EXEC_START_POST="ExecStartPost=/bin/bash $SCRIPT_DIR/setup-client-pod-whitelist-rules.sh"
  VBOX_CLIENT_EXEC_RELOAD="ExecReload=/bin/bash -c '$(which $DOCKER_EXEC) kill --signal HUP vbox-client && /bin/bash $SCRIPT_DIR/setup-client-pod-whitelist-rules.sh'"
else
  VBOX_CLIENT_EXEC_STOP_POST="ExecStopPost=/bin/bash $SCRIPT_DIR/setup-client-pod-ip-nft.sh clear"
  VBOX_CLIENT_EXEC_START_POST="ExecStartPost=/bin/bash $SCRIPT_DIR/setup-client-pod-ip-nft.sh"
  VBOX_CLIENT_EXEC_RELOAD="ExecReload=/bin/bash -c '$(which $DOCKER_EXEC) kill --signal HUP vbox-client && /bin/bash $SCRIPT_DIR/setup-client-pod-ip-nft.sh'"
fi

if [[ $FIND_PODLET_RESULT -eq 0 ]]; then
  PODLET_OPTIONS=(--install --wanted-by default.target --wants network-online.target --after network-online.target)
  for network in ${CADDY_NETWORK[@]}; do
    if [[ -e "$HOME/.config/containers/systemd/$network.network" ]]; then
      PODLET_OPTIONS+=(--after "$network-network.service" --wants "$network-network.service")
    fi
  done
  ${PODLET_RUN[@]} "${PODLET_OPTIONS[@]}" \
    $DOCKER_EXEC run --name vbox-client "${VBOX_DOCKER_OPRIONS[@]}" \
      "$VBOX_IMAGE_URL" -D /var/lib/vbox -C /etc/vbox/ run | \
      sed "/\\[Install/i [Service]\n$VBOX_CLIENT_EXEC_RELOAD" | \
      sed "/ExecReload=/a $VBOX_CLIENT_EXEC_STOP_POST" | \
      sed "/ExecStopPost=/a ExecStartPost=$(which $DOCKER_EXEC) exec vbox-client ln -f /usr/share/zoneinfo/Asia/Shanghai /etc/timezone" | \
      sed "/ExecStartPost=/a $VBOX_CLIENT_EXEC_START_POST" | \
      tee -p "$SYSTEMD_CONTAINER_DIR/vbox-client.container"
else
  $DOCKER_EXEC run -d --name vbox-client "${VBOX_DOCKER_OPRIONS[@]}" \
    "$VBOX_IMAGE_URL" -D /var/lib/vbox -C /etc/vbox/ run

  if [[ $? -ne 0 ]]; then
    echo "Failed to run vbox-client"
    exit 1
  fi

  $DOCKER_EXEC generate systemd vbox-client | \
    sed "/ExecStart=/a ExecStartPost=$(which $DOCKER_EXEC) exec vbox-client ln -f /usr/share/zoneinfo/Asia/Shanghai /etc/timezone" | \
    sed "/ExecStart=/a $VBOX_CLIENT_EXEC_STOP_POST" | \
    sed "/ExecStart=/a $VBOX_CLIENT_EXEC_START_POST" | \
    sed "/ExecReload=/d" | \
    sed "/ExecStart=/a $VBOX_CLIENT_EXEC_RELOAD" | \
  tee -p "$SYSTEMD_SERVICE_DIR/vbox-client.service"
  $DOCKER_EXEC container stop vbox-client
fi

if [[ "$SYSTEMD_SERVICE_DIR" == "/lib/systemd/system" ]]; then
  systemctl daemon-reload
else
  systemctl --user daemon-reload
fi

if [[ "$SYSTEMD_SERVICE_DIR" == "/lib/systemd/system" ]]; then
  if [[ $FIND_PODLET_RESULT -ne 0 ]]; then
    systemctl enable vbox-client.service
  fi
  systemctl start vbox-client.service
else
  if [[ $FIND_PODLET_RESULT -ne 0 ]]; then
    systemctl --user enable vbox-client.service
  fi
  systemctl --user start vbox-client.service
fi

if [[ "x$VBOX_UPDATE" != "x" ]] || [[ "x$ROUTER_IMAGE_UPDATE" != "x" ]]; then
  $DOCKER_EXEC image prune -a -f --filter "until=240h"
fi

# set -x
# CHECK_RUNNING=$($DOCKER_EXEC inspect --format="{{.State.Running}}" vbox-client)
# if [[ ! -z "$CHECK_RUNNING" ]] && [[ "$CHECK_RUNNING" != "false" ]] && [[ "$CHECK_RUNNING" != "0" ]]; then
#   sudo -u tools /bin/bash -i -c "systemctl --user restart container-adguard-home.service"
#   sudo -u tools /bin/bash -i -c "systemctl --user restart container-unbound.service"
# fi
