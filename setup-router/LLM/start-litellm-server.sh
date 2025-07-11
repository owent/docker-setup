#!/bin/bash

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"

# Require net.ipv4.ip_unprivileged_port_start=80 in /etc/sysctl.d/*.conf
# See https://github.com/containers/podman/blob/master/rootless.md

LLM_LITELLM_IMAGE_URL=ghcr.io/berriai/litellm:main-stable
# LLM_LITELLM_IMAGE_URL=ghcr.io/berriai/litellm:main-latest
# LLM_LITELLM_IMAGE_URL=litellm/litellm:v1.73.6-stable

if [[ "x$LLM_UPDATE" != "x" ]] || [[ "x$ROUTER_IMAGE_UPDATE" != "x" ]]; then
  podman pull $LLM_LITELLM_IMAGE_URL
  if [[ $? -ne 0 ]]; then
    echo "Pull $LLM_LITELLM_IMAGE_URL failed"
    exit 1
  fi
fi

#LLM_LITELLM_NETWORK=(internal-frontend)
if [[ -z "$LLM_LITELLM_WORKER_COUNT" ]]; then
  LLM_LITELLM_WORKER_COUNT=4
fi

if [[ -z "$LLM_LITELLM_PORT" ]]; then
  LLM_LITELLM_PORT=4000
fi

if [[ -z "$LLM_LITELLM_DATA_DIR" ]]; then
  LLM_LITELLM_DATA_DIR="$HOME/llm/litellm/data"
fi
mkdir -p "$LLM_LITELLM_DATA_DIR"

# Model List: https://github.com/BerriAI/litellm/blob/main/model_prices_and_context_window.json

# Datebase
# LLM_LITELLM_HOST_IP_ADDRESS=$(ip -o -4 addr show scope global | awk 'match($0, /inet\s+([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)/, ip) { print ip[1] }')
# LLM_LITELLM_DATABASE_URL=postgresql://<user>:<password>@<host>:<port>/<dbname>
# LLM_LITELLM_DATABASE_URL=postgresql://llm:<password>@$LLM_LITELLM_HOST_IP_ADDRESS:5432/litellm?schema=public

# Redis
# LLM_LITELLM_REDIS_HOST=$LLM_LITELLM_HOST_IP_ADDRESS
# LLM_LITELLM_REDIS_PORT=6379
# LLM_LITELLM_REDIS_PASSWORD=

# Password for root, maybe 123456
if [[ -e "$SCRIPT_DIR/llm-litellm.LITELLM_MASTER_KEY" ]]; then
  LLM_LITELLM_LITELLM_MASTER_KEY="$(cat "$SCRIPT_DIR/llm-litellm.LITELLM_MASTER_KEY")"
else
  LLM_LITELLM_LITELLM_MASTER_KEY="sk-$(head -c 12 /dev/urandom | base64 | tr '/' '_' | tr '+' '-')"
  echo "$LLM_LITELLM_LITELLM_MASTER_KEY" >"$SCRIPT_DIR/llm-litellm.LITELLM_MASTER_KEY"
fi

if [[ -e "$SCRIPT_DIR/llm-litellm.UI_PASSWORD" ]]; then
  LLM_LITELLM_UI_PASSWORD="$(cat "$SCRIPT_DIR/llm-litellm.UI_PASSWORD")"
else
  LLM_LITELLM_UI_PASSWORD="$(head -c 12 /dev/urandom | base64 | tr '/' '_' | tr '+' '-')"
  echo "$LLM_LITELLM_UI_PASSWORD" >"$SCRIPT_DIR/llm-litellm.UI_PASSWORD"
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
  -e LITELLM_MODE=PRODUCTION
  -e LITELLM_MASTER_KEY=$LLM_LITELLM_LITELLM_MASTER_KEY
  -e UI_USERNAME=owent
  -e UI_PASSWORD=$LLM_LITELLM_UI_PASSWORD
)
if [[ ! -z "$LLM_LITELLM_DATABASE_URL" ]]; then
  LLM_LITELLM_ENV=("${LLM_LITELLM_ENV[@]}" -e DATABASE_URL="$LLM_LITELLM_DATABASE_URL" -e STORE_MODEL_IN_DB=true)
fi
if [[ -e "$LLM_LITELLM_DATA_DIR/google-application-credentials.json" ]]; then
  LLM_LITELLM_ENV=("${LLM_LITELLM_ENV[@]}" -e GOOGLE_APPLICATION_CREDENTIALS="/app/google-application-credentials.json")
fi
if [[ ! -z "$LLM_LITELLM_REDIS_HOST" ]]; then
  LLM_LITELLM_ENV=("${LLM_LITELLM_ENV[@]}" -e REDIS_HOST="$LLM_LITELLM_REDIS_HOST")
fi
if [[ ! -z "$LLM_LITELLM_REDIS_PORT" ]]; then
  LLM_LITELLM_ENV=("${LLM_LITELLM_ENV[@]}" -e REDIS_PORT="$LLM_LITELLM_REDIS_PORT")
fi
if [[ ! -z "$LLM_LITELLM_REDIS_PASSWORD" ]]; then
  LLM_LITELLM_ENV=("${LLM_LITELLM_ENV[@]}" -e REDIS_PASSWORD="$LLM_LITELLM_REDIS_PASSWORD")
fi
if [[ ! -z "$LLM_LITELLM_SMTP_HOST" ]]; then
  LLM_LITELLM_ENV=("${LLM_LITELLM_ENV[@]}" -e SMTP_HOST="$LLM_LITELLM_SMTP_HOST")
fi
if [[ ! -z "$LLM_LITELLM_SMTP_PORT" ]]; then
  LLM_LITELLM_ENV=("${LLM_LITELLM_ENV[@]}" -e SMTP_PORT="$LLM_LITELLM_SMTP_PORT")
fi
if [[ ! -z "$LLM_LITELLM_SMTP_USERNAME" ]]; then
  LLM_LITELLM_ENV=("${LLM_LITELLM_ENV[@]}" -e SMTP_USERNAME="$LLM_LITELLM_SMTP_USERNAME")
fi
if [[ ! -z "$LLM_LITELLM_SMTP_PASSWORD" ]]; then
  LLM_LITELLM_ENV=("${LLM_LITELLM_ENV[@]}" -e SMTP_PASSWORD="$LLM_LITELLM_SMTP_PASSWORD")
fi
if [[ ! -z "$LLM_LITELLM_SMTP_SENDER_EMAIL" ]]; then
  LLM_LITELLM_ENV=("${LLM_LITELLM_ENV[@]}" -e SMTP_SENDER_EMAIL="$LLM_LITELLM_SMTP_SENDER_EMAIL")
fi

LLM_LITELLM_OPTIONS=(--mount type=bind,source=$LLM_LITELLM_DATA_DIR,target=/etc/litellm)
LLM_LITELLM_HAS_HOST_NETWORK=0
if [[ ! -z "$LLM_LITELLM_NETWORK" ]]; then
  for network in ${LLM_LITELLM_NETWORK[@]}; do
    LLM_LITELLM_OPTIONS+=("--network=$network")
    if [[ $network == "host" ]]; then
      LLM_LITELLMT_HAS_HOST_NETWORK=1
    fi
  done
fi
if [[ $LLM_LITELLM_HAS_HOST_NETWORK -eq 0 ]]; then
  LLM_LITELLM_OPTIONS+=(-p $LLM_LITELLM_PORT:$LLM_LITELLM_PORT)
fi

podman run -d --name llm-litellm --security-opt label=disable \
  "${LLM_LITELLM_ENV[@]}" "${LLM_LITELLM_OPTIONS[@]}" \
  $LLM_LITELLM_IMAGE_URL --port $LLM_LITELLM_PORT --config /etc/litellm/litellm-config.yaml --num_workers $LLM_LITELLM_WORKER_COUNT

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
