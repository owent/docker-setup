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

if [[ "x$CLOUDFLARE_ROOT_DIR" == "x" ]]; then
  CLOUDFLARE_ROOT_DIR="$RUN_HOME/cloudflare"
fi
mkdir -p "$CLOUDFLARE_ROOT_DIR"

CLOUDFLARE_ZERO_TRUST_TUNNEL_IMAGE="docker.io/cloudflare/cloudflared:latest"
if [[ "x$CLOUDFLARE_UPDATE" != "x" ]] || [[ "x$ROUTER_IMAGE_UPDATE" != "x" ]]; then
  podman pull $CLOUDFLARE_ZERO_TRUST_TUNNEL_IMAGE
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

systemctl --user --all | grep -F cloudflare-create-zero-trust-tunnel.service

if [[ $? -eq 0 ]]; then
  systemctl --user stop cloudflare-create-zero-trust-tunnel
  systemctl --user disable cloudflare-create-zero-trust-tunnel
fi

podman container exists cloudflare-create-zero-trust-tunnel >/dev/null 2>&1

if [[ $? -eq 0 ]]; then
  podman stop cloudflare-create-zero-trust-tunnel
  podman rm -f cloudflare-create-zero-trust-tunnel
fi

PODLET_IMAGE_URL="ghcr.io/containers/podlet:latest"
PODLET_RUN=($(which podlet 2>/dev/null))
FIND_PODLET_RESULT=$?
if [[ $FIND_PODLET_RESULT -ne 0 ]]; then
  (podman image inspect "$PODLET_IMAGE_URL" > /dev/null 2>&1 || podman pull "$PODLET_IMAGE_URL") && FIND_PODLET_RESULT=0 && PODLET_RUN=(podman run --rm "$PODLET_IMAGE_URL")
fi

if [[ $FIND_PODLET_RESULT -eq 0 ]]; then
  PODLET_OPTIONS=(--install --wanted-by default.target --wants network-online.target --after network-online.target)
  for network in ${EMBY_NETWORK[@]}; do
    if [[ -e "$HOME/.config/containers/systemd/$network.network" ]]; then
      PODLET_OPTIONS+=(--after "$network-network.service" --wants "$network-network.service")
    fi
  done
  ${PODLET_RUN[@]} "${PODLET_OPTIONS[@]}" \
    podman run -d --name cloudflare-create-zero-trust-tunnel --security-opt label=disable \
      -e "TZ=Asia/Shanghai" \
      $CLOUDFLARE_ZERO_TRUST_TUNNEL_IMAGE \
      tunnel --no-autoupdate run --token "$CLOUDFLARE_ZERO_TRUST_TUNNEL_TOKEN" | tee -p "$SYSTEMD_CONTAINER_DIR/cloudflare-create-zero-trust-tunnel.container"
else
  podman run -d --name cloudflare-create-zero-trust-tunnel --security-opt label=disable \
    -e "TZ=Asia/Shanghai" \
    $CLOUDFLARE_ZERO_TRUST_TUNNEL_IMAGE \
    tunnel --no-autoupdate run --token "$CLOUDFLARE_ZERO_TRUST_TUNNEL_TOKEN"
  podman generate systemd cloudflare-create-zero-trust-tunnel | tee -p "$SYSTEMD_SERVICE_DIR/cloudflare-create-zero-trust-tunnel.service"
  podman container stop cloudflare-create-zero-trust-tunnel
fi

if [[ "$SYSTEMD_SERVICE_DIR" == "/lib/systemd/system" ]]; then
  systemctl daemon-reload
else
  systemctl --user daemon-reload
fi

if [[ "$SYSTEMD_SERVICE_DIR" == "/lib/systemd/system" ]]; then
  if [[ $FIND_PODLET_RESULT -ne 0 ]]; then
    systemctl enable cloudflare-create-zero-trust-tunnel.service
  fi
  systemctl start cloudflare-create-zero-trust-tunnel.service
else
  if [[ $FIND_PODLET_RESULT -ne 0 ]]; then
    systemctl --user enable cloudflare-create-zero-trust-tunnel.service
  fi
  systemctl --user start cloudflare-create-zero-trust-tunnel.service
fi

if [[ "x$CLOUDFLARE_UPDATE" != "x" ]] || [[ "x$ROUTER_IMAGE_UPDATE" != "x" ]]; then
  podman image prune -a -f --filter "until=240h"
fi
