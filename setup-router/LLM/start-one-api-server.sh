#!/bin/bash

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"

# Require net.ipv4.ip_unprivileged_port_start=80 in /etc/sysctl.d/*.conf
# See https://github.com/containers/podman/blob/master/rootless.md

if [[ "x$LLM_UPDATE" != "x" ]] || [[ "x$ROUTER_IMAGE_UPDATE" != "x" ]]; then
  podman pull docker.io/justsong/one-api:latest
  if [[ $? -ne 0 ]]; then
    echo "Pull docker.io/justsong/one-api:latest failed"
    exit 1
  fi
fi

if [[ -z "$LLM_ONE_API_DATA_DIR" ]]; then
  LLM_ONE_API_DATA_DIR="$HOME/llm/one-api/data"
fi
mkdir -p "$LLM_ONE_API_DATA_DIR"

if [[ -z "$LLM_ONE_API_LOG_DIR" ]]; then
  LLM_ONE_API_LOG_DIR="$HOME/llm/one-api/log"
fi
mkdir -p "$LLM_ONE_API_LOG_DIR"

if [[ -z "$LLM_ONE_API_CACHE_DIR" ]]; then
  LLM_ONE_API_CACHE_DIR="$HOME/llm/one-api/cache"
fi
mkdir -p "$LLM_ONE_API_CACHE_DIR"

if [[ -z "$LLM_ONE_API_PORT" ]]; then
  LLM_ONE_API_PORT=3002
fi

# Datebase
# LLM_ONE_API_SQL_DSN

# Front
# LLM_ONE_API_FRONTEND_BASE_URL=https://owent-proxy.imwe.chat

# Per 3 minutes
if [[ -z "$LLM_ONE_API_GLOBAL_API_RATE_LIMIT" ]]; then
  LLM_ONE_API_GLOBAL_API_RATE_LIMIT=1800
fi
# Per 3 minutes
if [[ -z "$LLM_ONE_API_GLOBAL_WEB_RATE_LIMIT" ]]; then
  LLM_ONE_API_GLOBAL_WEB_RATE_LIMIT=1800
fi
if [[ -z "$LLM_ONE_API_RELAY_TIMEOUT" ]]; then
  LLM_ONE_API_RELAY_TIMEOUT=480
fi

# Password for root, maybe 123456
if [[ -e "$SCRIPT_DIR/llm-one-api.INITIAL_ROOT_TOKEN" ]]; then
  LLM_ONE_API_INITIAL_ROOT_TOKEN=$(cat "$SCRIPT_DIR/llm-one-api.INITIAL_ROOT_TOKEN")
else
  LLM_ONE_API_INITIAL_ROOT_TOKEN=$(head -c 12 /dev/urandom | base64)
  echo "$LLM_ONE_API_INITIAL_ROOT_TOKEN" >"$SCRIPT_DIR/llm-one-api.INITIAL_ROOT_TOKEN"
fi

if [[ "root" == "$(id -un)" ]]; then
  SYSTEMD_SERVICE_DIR=/lib/systemd/system
else
  SYSTEMD_SERVICE_DIR="$HOME/.config/systemd/user"
  mkdir -p "$SYSTEMD_SERVICE_DIR"
fi

if [[ "$SYSTEMD_SERVICE_DIR" == "/lib/systemd/system" ]]; then
  systemctl --all | grep -F llm-one-api.service >/dev/null 2>&1
  if [ $? -eq 0 ]; then
    systemctl stop llm-one-api.service
    systemctl disable llm-one-api.service
  fi
else
  export XDG_RUNTIME_DIR="/run/user/$UID"
  export DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR}/bus"

  # Maybe need run from host: loginctl enable-linger tools
  # see https://wiki.archlinux.org/index.php/Systemd/User
  # sudo loginctl enable-linger $RUN_USER
  systemctl --user --all | grep -F llm-one-api.service >/dev/null 2>&1
  if [ $? -eq 0 ]; then
    systemctl --user stop llm-one-api.service
    systemctl --user disable llm-one-api.service
  fi
fi

podman container inspect llm-one-api >/dev/null 2>&1

if [[ $? -eq 0 ]]; then
  podman stop llm-one-api
  podman rm -f llm-one-api
fi

if [[ "x$LLM_UPDATE" != "x" ]] || [[ "x$ROUTER_IMAGE_UPDATE" != "x" ]]; then
  podman image prune -a -f --filter "until=240h"
fi

LLM_ONE_API_ENV=(
  -e TZ=Asia/Shanghai
  -e TIKTOKEN_CACHE_DIR=/var/cache/one-api
  -e INITIAL_ROOT_TOKEN=$LLM_ONE_API_INITIAL_ROOT_TOKEN
  -e MEMORY_CACHE_ENABLED=true
  -e CHANNEL_UPDATE_FREQUENCY=120
  -e CHANNEL_TEST_FREQUENCY=120
  -e GLOBAL_API_RATE_LIMIT=$LLM_ONE_API_GLOBAL_API_RATE_LIMIT
  -e GLOBAL_WEB_RATE_LIMIT=$LLM_ONE_API_GLOBAL_WEB_RATE_LIMIT
  -e RELAY_TIMEOUT=$LLM_ONE_API_RELAY_TIMEOUT
)
if [[ ! -z "$LLM_ONE_API_SQL_DSN" ]]; then
  LLM_ONE_API_ENV=(${LLM_ONE_API_ENV[@]} -e SQL_DSN="$LLM_ONE_API_SQL_DSN")
fi
if [[ ! -z "$LLM_ONE_API_FRONTEND_BASE_URL" ]]; then
  LLM_ONE_API_ENV=(${LLM_ONE_API_ENV[@]} -e FRONTEND_BASE_URL="$LLM_ONE_API_FRONTEND_BASE_URL")
fi

podman run -d --name llm-one-api --security-opt label=disable \
  ${LLM_ONE_API_ENV[@]} \
  --mount type=bind,source=$LLM_ONE_API_LOG_DIR,target=/var/log/one-api \
  --mount type=bind,source=$LLM_ONE_API_DATA_DIR,target=/data \
  --mount type=bind,source=$LLM_ONE_API_CACHE_DIR,target=/var/cache/one-api \
  -p $LLM_ONE_API_PORT:3000 \
  docker.io/justsong/one-api:latest --log-dir /var/log/one-api

podman generate systemd llm-one-api | tee -p "$SYSTEMD_SERVICE_DIR/llm-one-api.service"
podman container stop llm-one-api

if [[ "$SYSTEMD_SERVICE_DIR" == "/lib/systemd/system" ]]; then
  systemctl enable llm-one-api.service
  systemctl daemon-reload
  systemctl start llm-one-api.service
else
  systemctl --user enable "$SYSTEMD_SERVICE_DIR/llm-one-api.service"
  systemctl --user daemon-reload
  systemctl --user start llm-one-api.service
fi
