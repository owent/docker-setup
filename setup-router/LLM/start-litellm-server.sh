#!/bin/bash

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"

# Require net.ipv4.ip_unprivileged_port_start=80 in /etc/sysctl.d/*.conf
# See https://github.com/containers/podman/blob/master/rootless.md

if [[ "x$LLM_UPDATE" != "x" ]] || [[ "x$ROUTER_IMAGE_UPDATE" != "x" ]]; then
  podman pull ghcr.io/berriai/litellm:main-latest
  if [[ $? -ne 0 ]]; then
    echo "Pull ghcr.io/berriai/litellm:main-latest failed"
    exit 1
  fi
fi

if [[ -z "$LLM_LITELLM_PORT" ]]; then
  LLM_LITELLM_PORT=4000
fi

if [[ -z "$LLM_LITELLM_DATA_DIR" ]]; then
  LLM_LITELLM_DATA_DIR="$HOME/llm/litellm/data"
fi
mkdir -p "$LLM_LITELLM_DATA_DIR"

# Datebase
# LLM_LITELLM_DATABASE_URL

# Password for root, maybe 123456
if [[ -e "$SCRIPT_DIR/llm-litellm.LITELLM_MASTER_KEY" ]]; then
  LLM_LITELLM_LITELLM_MASTER_KEY="$(cat "$SCRIPT_DIR/llm-litellm.LITELLM_MASTER_KEY")"
else
  LLM_LITELLM_LITELLM_MASTER_KEY="sk-$(head -c 12 /dev/urandom | base64)"
  echo "$LLM_LITELLM_LITELLM_MASTER_KEY" >"$SCRIPT_DIR/llm-litellm.LITELLM_MASTER_KEY"
fi

ln -f "litellm-config.yaml" "$LLM_LITELLM_DATA_DIR/" || cp -f "litellm-config.yaml" "$LLM_LITELLM_DATA_DIR/"

if [[ "root" == "$(id -un)" ]]; then
  SYSTEMD_SERVICE_DIR=/lib/systemd/system
else
  SYSTEMD_SERVICE_DIR="$HOME/.config/systemd/user"
  mkdir -p "$SYSTEMD_SERVICE_DIR"
fi

if [[ "$SYSTEMD_SERVICE_DIR" == "/lib/systemd/system" ]]; then
  systemctl --all | grep -F llm-litellm.service >/dev/null 2>&1
  if [ $? -eq 0 ]; then
    systemctl stop llm-litellm.service
    systemctl disable llm-litellm.service
  fi
else
  export XDG_RUNTIME_DIR="/run/user/$UID"
  export DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR}/bus"

  # Maybe need run from host: loginctl enable-linger tools
  # see https://wiki.archlinux.org/index.php/Systemd/User
  # sudo loginctl enable-linger $RUN_USER
  systemctl --user --all | grep -F llm-litellm.service >/dev/null 2>&1
  if [ $? -eq 0 ]; then
    systemctl --user stop llm-litellm.service
    systemctl --user disable llm-litellm.service
  fi
fi

podman container inspect llm-litellm >/dev/null 2>&1

if [[ $? -eq 0 ]]; then
  podman stop llm-litellm
  podman rm -f llm-litellm
fi

if [[ "x$LLM_UPDATE" != "x" ]] || [[ "x$ROUTER_IMAGE_UPDATE" != "x" ]]; then
  podman image prune -a -f --filter "until=240h"
fi

LLM_LITELLM_ENV=(
  -e TZ=Asia/Shanghai
  -e LITELLM_MASTER_KEY=$LLM_LITELLM_LITELLM_MASTER_KEY
)
if [[ ! -z "$LLM_LITELLM_DATABASE_URL" ]]; then
  LLM_LITELLM_ENV=(${LLM_LITELLM_ENV[@]} -e DATABASE_URL="$LLM_LITELLM_DATABASE_URL")
fi
if [[ -e "$LLM_LITELLM_DATA_DIR/google-application-credentials.json" ]]; then
  LLM_LITELLM_ENV=(${LLM_LITELLM_ENV[@]} -e GOOGLE_APPLICATION_CREDENTIALS="/app/google-application-credentials.json")
fi

podman run -d --name llm-litellm --security-opt label=disable \
  ${LLM_LITELLM_ENV[@]} \
  --mount type=bind,source=$LLM_LITELLM_DATA_DIR,target=/app \
  -p $LLM_LITELLM_PORT:4000 \
  ghcr.io/berriai/litellm:main-latest --port 4000 --config /app/litellm-config.yaml --num_workers 8

podman generate systemd llm-litellm | tee -p "$SYSTEMD_SERVICE_DIR/llm-litellm.service"
podman container stop llm-litellm

if [[ "$SYSTEMD_SERVICE_DIR" == "/lib/systemd/system" ]]; then
  systemctl enable llm-litellm.service
  systemctl daemon-reload
  systemctl start llm-litellm.service
else
  systemctl --user enable "$SYSTEMD_SERVICE_DIR/llm-litellm.service"
  systemctl --user daemon-reload
  systemctl --user start llm-litellm.service
fi
