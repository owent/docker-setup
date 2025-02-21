#!/bin/bash

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
source "$(dirname "$SCRIPT_DIR")/configure-router.sh"

export XDG_RUNTIME_DIR="/run/user/$UID"
export DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR}/bus"

if [[ -z "$RUN_HOME" ]]; then
  RUN_HOME="$HOME"
fi

if [[ -z "$BITWARDEN_PORT" ]]; then
  BITWARDEN_PORT=8381
fi

if [[ -z "$BITWARDEN_ETC_DIR" ]]; then
  BITWARDEN_ETC_DIR="$RUN_HOME/bitwarden/etc"
fi
mkdir -p "$BITWARDEN_ETC_DIR"

if [[ -z "$BITWARDEN_LOG_DIR" ]]; then
  BITWARDEN_LOG_DIR="$RUN_HOME/bitwarden/log"
fi
mkdir -p "$BITWARDEN_LOG_DIR"

if [[ -z "$BITWARDEN_DATA_DIR" ]]; then
  BITWARDEN_DATA_DIR="$RUN_HOME/bitwarden/data"
fi
mkdir -p "$BITWARDEN_DATA_DIR"

if [[ -n "$BITWARDEN_UPDATE" ]] || [[ -n "$ROUTER_IMAGE_UPDATE" ]]; then
  podman pull docker.io/vaultwarden/server:latest
fi

systemctl --user --all | grep -F container-bitwarden.service

if [[ $? -eq 0 ]]; then
  systemctl --user stop container-bitwarden
  systemctl --user disable container-bitwarden
fi

podman container exists bitwarden

if [[ $? -eq 0 ]]; then
  podman stop bitwarden
  podman rm -f bitwarden
fi

if [[ "x$BITWARDEN_UPDATE" != "x" ]] || [[ "x$ROUTER_IMAGE_UPDATE" != "x" ]]; then
  podman image prune -a -f --filter "until=240h"
fi

ADMIN_TOKEN=$(openssl rand -base64 48)

# -e SMTP_HOST=smtp.exmail.qq.com                                                   \
# -e SMTP_FROM=admin@owent.net                                                      \
## for mail servers that use port 465
# -e SMTP_PORT=465                                                                  \
# -e SMTP_SECURITY=force_tls                                                        \
## for mail servers that use port 587 (or sometimes 25)
# -e SMTP_PORT=587                                                                  \
# -e SMTP_SECURITY=starttls                                                         \
# -e SMTP_USERNAME=admin@owent.net                                                  \
# -e SMTP_PASSWORD=<TOKEN>                                                          \

## for mail servers that use port 465
# SMTP_PORT=465
# SMTP_SECURITY=force_tls

# -e ROCKET_WORKERS=8
# -e LOG_LEVEL=debug

podman run -d --name bitwarden --security-opt label=disable \
  -e SIGNUPS_ALLOWED=false -e WEBSOCKET_ENABLED=true \
  -e ROCKET_PORT=$BITWARDEN_PORT \
  -e INVITATIONS_ALLOWED=false -e LOG_FILE=/logs/bitwarden.log \
  -e ADMIN_TOKEN=$ADMIN_TOKEN \
  --mount type=bind,source=$BITWARDEN_LOG_DIR/,target=/logs/ \
  -v $BITWARDEN_DATA_DIR/:/data/:Z \
  -p 127.0.0.1:$BITWARDEN_PORT:$BITWARDEN_PORT/tcp \
  -p 127.0.0.1:$BITWARDEN_PORT:$BITWARDEN_PORT/udp \
  docker.io/vaultwarden/server:latest

podman exec bitwarden ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime

podman stop bitwarden

podman generate systemd --name bitwarden | tee $BITWARDEN_ETC_DIR/container-bitwarden.service

systemctl --user enable $BITWARDEN_ETC_DIR/container-bitwarden.service
systemctl --user restart container-bitwarden
