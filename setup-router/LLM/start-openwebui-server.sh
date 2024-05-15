#!/bin/bash

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"

# Require net.ipv4.ip_unprivileged_port_start=80 in /etc/sysctl.d/*.conf
# See https://github.com/containers/podman/blob/master/rootless.md

if [[ -z "$LLM_OPENWEBUI_WITH_GPU" ]]; then
  LLM_OPENWEBUI_WITH_GPU=0
fi

# OpenAI only or Ollama is on a Different Server: ghcr.io/open-webui/open-webui:main
# With GPU Support: ghcr.io/open-webui/open-webui:cuda
# With Bundled Ollama Support: ghcr.io/open-webui/open-webui:ollama

if [[ -z "$LLM_OPENWEBUI_IMAGE_URL" ]]; then
  if [[ "$LLM_OPENWEBUI_WITH_GPU" == "0" ]] || [[ "$LLM_OPENWEBUI_WITH_GPU" == "no" ]] || [[ "$LLM_OPENWEBUI_WITH_GPU" == "false" ]]; then
    LLM_OPENWEBUI_IMAGE_URL=ghcr.io/open-webui/open-webui:main
  else
    LLM_OPENWEBUI_IMAGE_URL=ghcr.io/open-webui/open-webui:cuda
  fi
fi

if [[ "x$LLM_UPDATE" != "x" ]] || [[ "x$ROUTER_IMAGE_UPDATE" != "x" ]]; then
  podman pull $LLM_OPENWEBUI_IMAGE_URL
  if [[ $? -ne 0 ]]; then
    echo "Pull $LLM_OPENWEBUI_IMAGE_URL failed"
    exit 1
  fi
fi

if [[ -z "$LLM_OPENWEBUI_DATA_DIR" ]]; then
  LLM_OPENWEBUI_DATA_DIR="$HOME/llm/openwebui/data"
fi
mkdir -p "$LLM_OPENWEBUI_DATA_DIR"

if [[ -z "$LLM_OPENWEBUI_OLLAMA_DIR" ]]; then
  LLM_OPENWEBUI_OLLAMA_DIR="$HOME/llm/openwebui/ollama"
fi
mkdir -p "$LLM_OPENWEBUI_OLLAMA_DIR"

if [[ -z "$LLM_OPENWEBUI_PORT" ]]; then
  LLM_OPENWEBUI_PORT=3006
fi

if [[ -z "$LLM_OPENWEBUI_WEBUI_AUTH" ]]; then
  LLM_OPENWEBUI_WEBUI_AUTH="true"
fi

if [[ -z "$LLM_OPENWEBUI_WEBUI_NAME" ]]; then
  LLM_OPENWEBUI_WEBUI_NAME="OWenT WebUI"
fi

if [[ -z "$LLM_OPENWEBUI_ENABLE_SIGNUP" ]]; then
  LLM_OPENWEBUI_ENABLE_SIGNUP="false"
fi

if [[ -z "$LLM_OPENWEBUI_DEFAULT_USER_ROL" ]]; then
  LLM_OPENWEBUI_DEFAULT_USER_ROL="pending"
fi

# LLM_OPENWEBUI_MODEL_FILTER_LIST="llama3:instruct;gemma:instruct"
# LLM_OPENWEBUI_WEBHOOK_URL= # Sets a webhook for integration with Slack/Microsoft Teams.
if [[ -z "$LLM_OPENWEBUI_ENABLE_ADMIN_EXPORT" ]]; then
  LLM_OPENWEBUI_ENABLE_ADMIN_EXPORT="true"
fi

# https://docs.peewee-orm.com/en/latest/peewee/playhouse.html#db-url
# LLM_OPENWEBUI_HOST_IP_ADDRESS=$(ip -o -4 addr show scope global | awk 'match($0, /inet\s+([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)/, ip) { print ip[1] }')
# LLM_OPENWEBUI_DATABASE_URL=sqlite:///${DATA_DIR}/webui.db # postgresql://<user>:<password>@<host>:<port>/<dbname>
# LLM_LITELLM_DATABASE_URL=postgresql://llm:<password>@$LLM_LITELLM_HOST_IP_ADDRESS:5432/openwebui?schema=public

# Password for root, maybe t0p-s3cr3t
if [[ -e "$SCRIPT_DIR/openwebui.WEBUI_SECRET_KEY" ]]; then
  LLM_OPENWEBUI_WEBUI_SECRET_KEY=$(cat "$SCRIPT_DIR/openwebui.WEBUI_SECRET_KEY")
else
  LLM_OPENWEBUI_WEBUI_SECRET_KEY="t0p-$(head -c 12 /dev/urandom | base64)"
  echo "$LLM_OPENWEBUI_WEBUI_SECRET_KEY" >"$SCRIPT_DIR/openwebui.WEBUI_SECRET_KEY"
fi

if [[ "root" == "$(id -un)" ]]; then
  SYSTEMD_SERVICE_DIR=/lib/systemd/system
else
  SYSTEMD_SERVICE_DIR="$HOME/.config/systemd/user"
  mkdir -p "$SYSTEMD_SERVICE_DIR"
fi

if [[ "$SYSTEMD_SERVICE_DIR" == "/lib/systemd/system" ]]; then
  systemctl --all | grep -F llm-openwebui.service >/dev/null 2>&1
  if [ $? -eq 0 ]; then
    systemctl stop llm-openwebui.service
    systemctl disable llm-openwebui.service
  fi
else
  export XDG_RUNTIME_DIR="/run/user/$UID"
  export DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR}/bus"

  # Maybe need run from host: loginctl enable-linger tools
  # see https://wiki.archlinux.org/index.php/Systemd/User
  # sudo loginctl enable-linger $RUN_USER
  systemctl --user --all | grep -F llm-openwebui.service >/dev/null 2>&1
  if [ $? -eq 0 ]; then
    systemctl --user stop llm-openwebui.service
    systemctl --user disable llm-openwebui.service
  fi
fi

podman container inspect llm-openwebui >/dev/null 2>&1

if [[ $? -eq 0 ]]; then
  podman stop llm-openwebui
  podman rm -f llm-openwebui
fi

if [[ "x$LLM_UPDATE" != "x" ]] || [[ "x$ROUTER_IMAGE_UPDATE" != "x" ]]; then
  podman image prune -a -f --filter "until=240h"
fi

LLM_OPENWEBUI_ENV=(
  -e TZ=Asia/Shanghai
  -e PORT=$LLM_OPENWEBUI_PORT
  -e WEBUI_SECRET_KEY=$LLM_OPENWEBUI_WEBUI_SECRET_KEY
  -e WEBUI_AUTH=$LLM_OPENWEBUI_WEBUI_AUTH
  -e "WEBUI_NAME=$LLM_OPENWEBUI_WEBUI_NAME"
  -e ENABLE_SIGNUP=$LLM_OPENWEBUI_ENABLE_SIGNUP
  -e DEFAULT_USER_ROL=$LLM_OPENWEBUI_DEFAULT_USER_ROL
  -e ENABLE_ADMIN_EXPORT=$LLM_OPENWEBUI_ENABLE_ADMIN_EXPORT
)
if [[ ! -z "$LLM_OPENWEBUI_WITH_GPU" ]] && [[ "$LLM_OPENWEBUI_WITH_GPU" != "0" ]] && [[ "$LLM_OPENWEBUI_WITH_GPU" != "no" ]] && [[ "$LLM_OPENWEBUI_WITH_GPU" != "false" ]]; then
  LLM_OPENWEBUI_ENV=("${LLM_OPENWEBUI_ENV[@]}" --gpus=all) # --add-host=host.docker.internal:host-gateway)
fi

if [[ ! -z "$LLM_OPENWEBUI_MODEL_FILTER_LIST" ]]; then
  LLM_OPENWEBUI_ENV=("${LLM_OPENWEBUI_ENV[@]}" -e MODEL_FILTER_LIST="$LLM_OPENWEBUI_MODEL_FILTER_LIST")
fi
if [[ ! -z "$LLM_OPENWEBUI_WEBHOOK_URL" ]]; then
  LLM_OPENWEBUI_ENV=("${LLM_OPENWEBUI_ENV[@]}" -e WEBHOOK_URL="$LLM_OPENWEBUI_WEBHOOK_URL")
fi
if [[ ! -z "$LLM_OPENWEBUI_DATABASE_URL" ]]; then
  LLM_OPENWEBUI_ENV=("${LLM_OPENWEBUI_ENV[@]}" -e DATABASE_URL="$LLM_OPENWEBUI_DATABASE_URL")
fi

# LLM_OPENWEBUI_ENABLE_IMAGE_GENERATION=true
# LLM_OPENWEBUI_IMAGE_GENERATION_ENGINE=openai

LLM_OPENWEBUI_TEST_ENV=(
  OLLAMA_BASE_URL
  OLLAMA_BASE_URLS
  K8S_FLAG
  USE_OLLAMA_DOCKER

  OLLAMA_API_BASE_URL
  OPENAI_API_KEY
  OPENAI_API_BASE_URL
  OPENAI_API_BASE_URLS
  OPENAI_API_KEYS

  ENABLE_IMAGE_GENERATION
  IMAGE_GENERATION_ENGINE # openai,comfyui,automatic1111
  AUTOMATIC1111_BASE_URL
  COMFYUI_BASE_URL
  IMAGES_OPENAI_API_KEY
  IMAGES_OPENAI_API_BASE_URL
  IMAGE_SIZE # 512x512
  IMAGE_STEPS
  IMAGE_GENERATION_MODEL

  ENABLE_LITELLM
  LITELLM_PROXY_PORT
  LITELLM_PROXY_HOST
)

for TEST_ENV in "${LLM_OPENWEBUI_TEST_ENV[@]}"; do
  TEST_ENV_KEY="LLM_OPENWEBUI_${TEST_ENV}"
  if [[ ! -z "${!TEST_ENV_KEY}" ]]; then
    LLM_OPENWEBUI_ENV=("${LLM_OPENWEBUI_ENV[@]}" -e "$TEST_ENV=${!TEST_ENV_KEY}")
  fi
done

podman run -d --name llm-openwebui --security-opt label=disable \
  ${LLM_OPENWEBUI_ENV[@]} \
  --mount type=bind,source=$LLM_OPENWEBUI_DATA_DIR,target=/app/backend/data \
  --mount type=bind,source=$LLM_OPENWEBUI_OLLAMA_DIR,target=/root/.ollama \
  -p $LLM_OPENWEBUI_PORT:$LLM_OPENWEBUI_PORT \
  $LLM_OPENWEBUI_IMAGE_URL

podman generate systemd llm-openwebui | tee -p "$SYSTEMD_SERVICE_DIR/llm-openwebui.service"
podman container stop llm-openwebui

if [[ "$SYSTEMD_SERVICE_DIR" == "/lib/systemd/system" ]]; then
  systemctl enable llm-openwebui.service
  systemctl daemon-reload
  systemctl start llm-openwebui.service
else
  systemctl --user enable "$SYSTEMD_SERVICE_DIR/llm-openwebui.service"
  systemctl --user daemon-reload
  systemctl --user start llm-openwebui.service
fi
