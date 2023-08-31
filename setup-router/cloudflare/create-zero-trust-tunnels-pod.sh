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

systemctl --user --all | grep -F container-cloudflare-create-zero-trust-tunnel.service

if [[ $? -eq 0 ]]; then
  systemctl --user stop container-cloudflare-create-zero-trust-tunnel
  systemctl --user disable container-cloudflare-create-zero-trust-tunnel
fi

podman container exists cloudflare-create-zero-trust-tunnel >/dev/null 2>&1

if [[ $? -eq 0 ]]; then
  podman stop cloudflare-create-zero-trust-tunnel
  podman rm -f cloudflare-create-zero-trust-tunnel
fi

if [[ "x$REDIS_UPDATE" != "x" ]] || [[ "x$ROUTER_IMAGE_UPDATE" != "x" ]]; then
  podman image prune -a -f --filter "until=240h"
fi

podman run -d --name cloudflare-create-zero-trust-tunnel --security-opt label=disable \
  -e "TZ=Asia/Shanghai" \
  $CLOUDFLARE_ZERO_TRUST_TUNNEL_IMAGE \
  tunnel --no-autoupdate run --token "$CLOUDFLARE_ZERO_TRUST_TUNNEL_TOKEN"

podman stop cloudflare-create-zero-trust-tunnel

podman generate systemd --name cloudflare-create-zero-trust-tunnel | tee $CLOUDFLARE_ROOT_DIR/container-cloudflare-create-zero-trust-tunnel.service

systemctl --user enable $CLOUDFLARE_ROOT_DIR/container-cloudflare-create-zero-trust-tunnel.service
systemctl --user restart container-cloudflare-create-zero-trust-tunnel
