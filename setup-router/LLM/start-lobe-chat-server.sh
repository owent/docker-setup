#!/bin/bash

# https://github.com/lobehub/lobe-chat

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"

LLM_LOBECHAT_IMAGE_URL=docker.io/lobehub/lobe-chat:latest

if [[ "x$LLM_UPDATE" != "x" ]] || [[ "x$ROUTER_IMAGE_UPDATE" != "x" ]]; then
  podman pull $LLM_LOBECHAT_IMAGE_URL
  if [[ $? -ne 0 ]]; then
    echo "Pull $LLM_LOBECHAT_IMAGE_URL failed"
    exit 1
  fi
fi

# Providers: https://lobehub.com/zh/docs/self-hosting/environment-variables/model-provider
# Model list: https://lobehub.com/docs/self-hosting/advanced/model-list

# LLM_LOBE_CHAT_OPENAI_API_KEY=sk-
# LLM_LOBE_CHAT_OPENAI_PROXY_URL=https://litellm.imwe.chat/v1 # https://api.openai.com/v1
# LLM_LOBE_CHAT_API_KEY_SELECT_MODE=random # random,turn
# See https://github.com/lobehub/lobe-chat/blob/main/src/config/modelProviders/openai.ts
# LLM_LOBE_CHAT_OPENAI_MODEL_LIST="-all,+gpt-3.5-turbo,+gpt-3.5-turbo-16k,+gpt-4o,+gpt-4-turbo,+gemini-pro,+gemini-pro-vision"
# LLM_LOBE_CHAT_OPENAI_MODEL_LIST="-all,+gpt-3.5-turbo=gpt-3.5-turbo<16384:fc>,+gpt-3.5-turbo-16k,+gpt-4o=gpt-4o<128000:fc:vision:file>"

# LLM_LOBE_CHAT_AZURE_API_KEY=
# LLM_LOBE_CHAT_AZURE_ENDPOINT= # https://owent-us.openai.azure.com/
# LLM_LOBE_CHAT_AZURE_MODEL_LIST=random # random,turn

# LLM_LOBE_CHAT_GOOGLE_API_KEY=
# LLM_LOBE_CHAT_GOOGLE_PROXY_URL= # https://generativelanguage.googleapis.com

# LLM_LOBE_CHAT_OLLAMA_PROXY_URL= # http://127.0.0.1:11434
# LLM_LOBE_CHAT_OLLAMA_MODEL_LIST=random # random,turn

# https://chat-plugins.lobehub.com/
# LLM_LOBE_CHAT_PLUGINS_INDEX_URL=https://chat-plugins.lobehub.com # random,turn
# LLM_LOBE_CHAT_PLUGIN_SETTINGS= # search-engine:SERPAPI_API_KEY=xxxxx,plugin-2:key1=value1;key2=value2

# LLM_LOBE_CHAT_AGENTS_INDEX_URL=https://chat-agents.lobehub.com # random,turn

# LLM_LOBE_CHAT_ACCESS_CODE=CODE1,CODE2,CODE3
if [[ -z "$LLM_LOBE_CHAT_PORT" ]]; then
  LLM_LOBE_CHAT_PORT=3210
fi

# https://github.com/lobehub/lobe-chat/discussions/913
# LLM_LOBE_CHAT_DEFAULT_AGENT_CONFIG="model=gpt-3.5-turbo;params.max_tokens=16384;plugins=search-engine,lobe-image-designer,bilibili,realtime-weather,steam,website-crawler"

# LLM_LOBE_CHAT_ENABLE_OAUTH_SSO=1
# Auth: https://lobehub.com/zh/docs/self-hosting/environment-variables/auth
if [[ -e "$SCRIPT_DIR/llm-lobechat.NEXTAUTH_SECRET" ]]; then
  LLM_LOBE_CHAT_NEXTAUTH_SECRET="$(cat "$SCRIPT_DIR/llm-lobechat.NEXTAUTH_SECRET")"
else
  LLM_LOBE_CHAT_NEXTAUTH_SECRET="$(head -c 32 /dev/urandom | base64 | tr '/' '_' | tr '+' '-')"
  echo "$LLM_LOBE_CHAT_NEXTAUTH_SECRET" >"$SCRIPT_DIR/llm-lobechat.NEXTAUTH_SECRET"
fi
# LLM_LOBE_CHAT_NEXTAUTH_URL=
# https://lobehub.com/zh/docs/self-hosting/advanced/sso-providers/microsoft-entra-id
# https://lobehub.com/zh/docs/self-hosting/advanced/sso-providers/github
# LLM_LOBE_CHAT_NEXT_AUTH_SSO_PROVIDERS=azure-ad,github
# Auth: Microsoft Entra ID
# LLM_LOBE_CHAT_AZURE_AD_CLIENT_ID=
# LLM_LOBE_CHAT_AZURE_AD_CLIENT_SECRET=
# LLM_LOBE_CHAT_AZURE_AD_TENANT_ID=
# Auth: Github
# LLM_LOBE_CHAT_GITHUB_CLIENT_ID=
# LLM_LOBE_CHAT_GITHUB_CLIENT_SECRET=

# ====================================== start deploy ======================================
# Access Code
if [[ -e "$SCRIPT_DIR/llm-lobechat.ACCESS_CODE" ]]; then
  LLM_LOBE_CHAT_ACCESS_CODE="$(cat "$SCRIPT_DIR/llm-lobechat.ACCESS_CODE")"
else
  LLM_LOBE_CHAT_ACCESS_CODE="$(head -c 15 /dev/urandom | base64 | tr '/' '_' | tr '+' '-')"
  for ((i = 0; i < 5; ++i)); do
    LLM_LOBE_CHAT_ACCESS_CODE="$LLM_LOBE_CHAT_ACCESS_CODE,$(head -c 15 /dev/urandom | base64 | tr '/' '_' | tr '+' '-')"
  done
  echo "$LLM_LOBE_CHAT_ACCESS_CODE" >"$SCRIPT_DIR/llm-lobechat.ACCESS_CODE"
fi

if [[ "root" == "$(id -un)" ]]; then
  SYSTEMD_SERVICE_DIR=/lib/systemd/system
else
  SYSTEMD_SERVICE_DIR="$HOME/.config/systemd/user"
  mkdir -p "$SYSTEMD_SERVICE_DIR"
fi

if [[ "$SYSTEMD_SERVICE_DIR" == "/lib/systemd/system" ]]; then
  systemctl --all | grep -F llm-lobechat.service >/dev/null 2>&1
  if [ $? -eq 0 ]; then
    systemctl stop llm-lobechat.service
    systemctl disable llm-lobechat.service
  fi
else
  export XDG_RUNTIME_DIR="/run/user/$UID"
  export DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR}/bus"

  # Maybe need run from host: loginctl enable-linger tools
  # see https://wiki.archlinux.org/index.php/Systemd/User
  # sudo loginctl enable-linger $RUN_USER
  systemctl --user --all | grep -F llm-lobechat.service >/dev/null 2>&1
  if [ $? -eq 0 ]; then
    systemctl --user stop llm-lobechat.service
    systemctl --user disable llm-lobechat.service
  fi
fi

podman container inspect llm-lobechat >/dev/null 2>&1

if [[ $? -eq 0 ]]; then
  podman stop llm-lobechat
  podman rm -f llm-lobechat
fi

if [[ "x$LLM_UPDATE" != "x" ]] || [[ "x$ROUTER_IMAGE_UPDATE" != "x" ]]; then
  podman image prune -a -f --filter "until=240h"
fi

LLM_LOBE_CHAT_ENV=(
  -e TZ=Asia/Shanghai
  -e PORT=$LLM_LOBE_CHAT_PORT
  -e OPENAI_API_KEY=$LLM_LOBE_CHAT_OPENAI_API_KEY
  -e OPENAI_PROXY_URL=$LLM_LOBE_CHAT_OPENAI_PROXY_URL
  -e "ACCESS_CODE=$LLM_LOBE_CHAT_ACCESS_CODE"
  -e "NEXTAUTH_SECRET=$LLM_LOBE_CHAT_NEXTAUTH_SECRET"
)

LLM_LOBE_CHAT_TEST_ENV=(
  API_KEY_SELECT_MODE
  NEXT_PUBLIC_BASE_PATH
  DEFAULT_AGENT_CONFIG

  PLUGINS_INDEX_URL
  PLUGIN_SETTINGS

  AGENTS_INDEX_URL

  # Providers
  OPENAI_API_KEY
  OPENAI_PROXY_URL
  OPENAI_MODEL_LIST

  AZURE_API_KEY
  AZURE_ENDPOINT
  AZURE_API_VERSION
  AZURE_MODEL_LIST

  GOOGLE_API_KEY
  GOOGLE_PROXY_URL

  ANTHROPIC_API_KEY
  ANTHROPIC_PROXY_URL

  AWS_ACCESS_KEY_ID
  AWS_SECRET_ACCESS_KEY
  AWS_REGION

  OPENROUTER_API_KEY
  OPENROUTER_MODEL_LIST

  TOGETHERAI_API_KEY
  TOGETHERAI_MODEL_LIST

  OLLAMA_PROXY_URL
  OLLAMA_MODEL_LIST

  MOONSHOT_API_KEY

  MINIMAX_API_KEY

  MISTRAL_API_KEY

  GROQ_API_KEY

  ZHIPU_API_KEY

  ZEROONE_API_KEY

  # Authorization
  ENABLE_OAUTH_SSO
  NEXTAUTH_SECRET
  NEXTAUTH_URL
  NEXT_AUTH_SSO_PROVIDERS

  # https://lobehub.com/docs/self-hosting/advanced/sso-providers/microsoft-entra-id
  AZURE_AD_CLIENT_ID
  AZURE_AD_CLIENT_SECRET
  AZURE_AD_TENANT_ID

  # https://lobehub.com/docs/self-hosting/advanced/sso-providers/github
  GITHUB_CLIENT_ID
  GITHUB_CLIENT_SECRET

  # Analytics
  ENABLE_GOOGLE_ANALYTICS
  GOOGLE_ANALYTICS_MEASUREMENT_ID
)

for TEST_ENV in "${LLM_LOBE_CHAT_TEST_ENV[@]}"; do
  TEST_ENV_KEY="LLM_LOBE_CHAT_${TEST_ENV}"
  if [[ ! -z "${!TEST_ENV_KEY}" ]]; then
    LLM_LOBE_CHAT_ENV=("${LLM_LOBE_CHAT_ENV[@]}" -e "$TEST_ENV=${!TEST_ENV_KEY}")
  fi
done

podman run -d --name llm-lobechat --security-opt label=disable \
  "${LLM_LOBE_CHAT_ENV[@]}" \
  -p $LLM_LOBE_CHAT_PORT:3210 \
  $LLM_LOBECHAT_IMAGE_URL

podman generate systemd llm-lobechat | tee -p "$SYSTEMD_SERVICE_DIR/llm-lobechat.service"
podman container stop llm-lobechat

if [[ "$SYSTEMD_SERVICE_DIR" == "/lib/systemd/system" ]]; then
  systemctl enable llm-lobechat.service
  systemctl daemon-reload
  systemctl start llm-lobechat.service
else
  systemctl --user enable "$SYSTEMD_SERVICE_DIR/llm-lobechat.service"
  systemctl --user daemon-reload
  systemctl --user start llm-lobechat.service
fi
