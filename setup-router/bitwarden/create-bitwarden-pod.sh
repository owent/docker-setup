#!/bin/bash

if [[ -e "/opt/nftables/sbin" ]]; then
  export PATH=/opt/nftables/sbin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/bin/site_perl:/usr/bin/vendor_perl:/usr/bin/core_perl
else
  export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/bin/site_perl:/usr/bin/vendor_perl:/usr/bin/core_perl
fi

export XDG_RUNTIME_DIR="/run/user/$UID"
export DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR}/bus"

RUN_USER=$(id -un)
# sudo loginctl enable-linger $RUN_USER

if [[ "x$RUN_USER" == "x" ]] || [[ "x$RUN_USER" == "xroot" ]]; then
  echo -e "\033[1;32m$0 can not run with\033[0;m \033[1;31m$RUN_USER\033[0;m"
  exit 1
fi

RUN_HOME=$(cat /etc/passwd | awk "BEGIN{FS=\":\"} \$1 == \"$RUN_USER\" { print \$6 }")

if [[ "x$RUN_HOME" == "x" ]]; then
  RUN_HOME="$HOME"
fi

if [[ "x$BITWARDEN_ETC_DIR" == "x" ]]; then
  BITWARDEN_ETC_DIR="$RUN_HOME/bitwarden/etc"
fi
mkdir -p "$BITWARDEN_ETC_DIR"

if [[ "x$BITWARDEN_LOG_DIR" == "x" ]]; then
  BITWARDEN_LOG_DIR="$RUN_HOME/bitwarden/log"
fi
mkdir -p "$BITWARDEN_LOG_DIR"

if [[ "x$BITWARDEN_DATA_DIR" == "x" ]]; then
  BITWARDEN_DATA_DIR="$RUN_HOME/bitwarden/data"
fi
mkdir -p "$BITWARDEN_DATA_DIR"

systemctl --user --all | grep -F container-bitwarden.service

if [[ $? -eq 0 ]]; then
  systemctl --user stop container-bitwarden
  systemctl --user disable container-bitwarden
fi

podman container inspect bitwarden >/dev/null 2>&1

if [[ $? -eq 0 ]]; then
  podman stop bitwarden
  podman rm -f bitwarden
fi

if [[ "x$BITWARDEN_UPDATE" != "x" ]] || [[ "x$ROUTER_IMAGE_UPDATE" != "x" ]]; then
  podman image inspect docker.io/vaultwarden/server:latest >/dev/null 2>&1
  if [[ $? -eq 0 ]]; then
    podman image rm -f docker.io/vaultwarden/server:latest
  fi
fi

podman pull docker.io/vaultwarden/server:latest

ADMIN_TOKEN=$(openssl rand -base64 48)

# -e SMTP_HOST=smtp.exmail.qq.com                                                   \
# -e SMTP_FROM=admin@owent.net                                                      \
# -e SMTP_PORT=465                                                                  \
# -e SMTP_SSL=true                                                                  \
# -e SMTP_USERNAME=admin@owent.net                                                  \
# -e SMTP_PASSWORD=<TOKEN>                                                          \

# -e ROCKET_WORKERS=8

podman run -d --name bitwarden --security-opt label=disable \
  -e SIGNUPS_ALLOWED=false -e WEBSOCKET_ENABLED=true \
  -e ROCKET_ADDRESS=127.0.0.1 -e ROCKET_PORT=8381 \
  -e WEBSOCKET_ADDRESS=127.0.0.1 -e WEBSOCKET_PORT=8382 \
  -e INVITATIONS_ALLOWED=false -e LOG_FILE=/logs/bitwarden.log \
  -e ADMIN_TOKEN=$ADMIN_TOKEN \
  --mount type=bind,source=$BITWARDEN_LOG_DIR/,target=/logs/ \
  -v $BITWARDEN_DATA_DIR/:/data/:Z \
  --network=host docker.io/vaultwarden/server:latest

podman exec bitwarden ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime

podman generate systemd --name bitwarden | tee $BITWARDEN_ETC_DIR/container-bitwarden.service

systemctl --user enable $BITWARDEN_ETC_DIR/container-bitwarden.service
systemctl --user restart container-bitwarden
