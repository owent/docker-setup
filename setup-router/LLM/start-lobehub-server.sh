#!/bin/bash

# https://github.com/lobehub/lobe-chat

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"

LLM_LOBECHAT_IMAGE_URL=docker.io/lobehub/lobehub:latest
#LLM_LOBEHUB_NETWORK=(internal-frontend internal-backend)

if [[ "x$LLM_UPDATE" != "x" ]] || [[ "x$ROUTER_IMAGE_UPDATE" != "x" ]]; then
  podman pull $LLM_LOBECHAT_IMAGE_URL
  if [[ $? -ne 0 ]]; then
    echo "Pull $LLM_LOBECHAT_IMAGE_URL failed"
    exit 1
  fi
fi

# Providers: https://lobehub.com/zh/docs/self-hosting/environment-variables/model-provider
# Model list: https://lobehub.com/docs/self-hosting/advanced/model-list

# LLM_LOBEHUB_OPENAI_API_KEY=sk-
# LLM_LOBEHUB_OPENAI_PROXY_URL=https://litellm.imwe.chat/v1 # https://api.openai.com/v1
# LLM_LOBEHUB_API_KEY_SELECT_MODE=random # random,turn
# See https://github.com/lobehub/lobe-chat/blob/main/src/config/modelProviders/openai.ts
# Model list: https://lobehub.com/docs/self-hosting/advanced/model-list
LLM_LOBEHUB_OPENAI_MODEL_LIST_ARRAY=(
    "gemini-flash=gemini-flash<1048576:vision:reasoning:search:fc:file>"
    "gemini-pro=gemini-pro<1048576:vision:reasoning:search:fc:file>"
    "claude-sonnet-4=claude-sonnet-4<200000:vision:reasoning:search:fc:file>"
    "claude-opus-4.5=claude-opus-4.5<200000:vision:reasoning:search:fc:file>"
    "gpt-5=gpt-5<400000:vision:reasoning:search:fc:file>"
    "gpt-5-mini=gpt-5-mini<400000:vision:reasoning:search:fc:file>"
    "gpt-5-nano=gpt-5-nano<400000:vision:reasoning:fc:file>"
    # "gpt-5"
    # "gpt-5-mini"
    # "gpt-5-nano"
    "o3=o3<200000:vision:search:reasoning:fc:file>"
    "o3-mini=o3-mini<200000:fc:file>"
    "o4-mini=o4-mini<200000:vision:reasoning:fc:file>"
    "o1"
    "o1-mini"
    "gpt-4o"
)
LLM_LOBEHUB_OPENAI_MODEL_LIST="-all"
for MODEL_SETTING in "${LLM_LOBEHUB_OPENAI_MODEL_LIST_ARRAY[@]}"; do
    LLM_LOBEHUB_OPENAI_MODEL_LIST+=",+$MODEL_SETTING"
done

# LLM_LOBEHUB_AZURE_API_KEY=
# LLM_LOBEHUB_AZURE_ENDPOINT= # https://owent-us.openai.azure.com/
# LLM_LOBEHUB_AZURE_MODEL_LIST=random # random,turn

# LLM_LOBEHUB_GOOGLE_API_KEY=
# LLM_LOBEHUB_GOOGLE_PROXY_URL= # https://generativelanguage.googleapis.com

# LLM_LOBEHUB_HUNYUAN_API_KEY=
# LLM_LOBEHUB_HUNYUAN_MODEL_LIST="-all,+hunyuan-lite,,+hunyuan-standard,,+hunyuan-standard-256K,,+hunyuan-turbo" #https://console.cloud.tencent.com/hunyuan

# LLM_LOBEHUB_OLLAMA_PROXY_URL= # http://127.0.0.1:11434
# LLM_LOBEHUB_OLLAMA_MODEL_LIST=random # random,turn

# https://chat-plugins.lobehub.com/
# LLM_LOBEHUB_PLUGINS_INDEX_URL=https://chat-plugins.lobehub.com # random,turn
# LLM_LOBEHUB_PLUGIN_SETTINGS= # search-engine:SERPAPI_API_KEY=xxxxx,plugin-2:key1=value1;key2=value2

# LLM_LOBEHUB_AGENTS_INDEX_URL=https://chat-agents.lobehub.com # random,turn

if [[ -z "$LLM_LOBEHUB_PORT" ]]; then
  LLM_LOBEHUB_PORT=3210
fi

# https://github.com/lobehub/lobe-chat/discussions/913
# LLM_LOBEHUB_DEFAULT_AGENT_CONFIG="model=gpt-3.5-turbo;params.max_tokens=16384;plugins=lobe-image-designer,lobe-artifacts,lobe-web-browsing,bilibili,realtime-weather,steam"

# ====================================== start deploy ======================================
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

LLM_LOBEHUB_ENV=(
  -e TZ=Asia/Shanghai
  -e PORT=$LLM_LOBEHUB_PORT
)

LLM_LOBEHUB_TEST_ENV=(
  APP_URL
  API_KEY_SELECT_MODE
  DEFAULT_AGENT_CONFIG

  PLUGINS_INDEX_URL
  PLUGIN_SETTINGS

  AGENTS_INDEX_URL

  # DB
  KEY_VAULTS_SECRET
  DATABASE_URL # postgres://postgres:mysecretpassword@my-postgres:5432/postgres

  REDIS_URL # redis://localhost:6379, rediss://localhost:6379, redis://:password@localhost:6379/0
  REDIS_PREFIX
  REDIS_TLS
  REDIS_PASSWORD
  REDIS_USERNAME
  REDIS_DATABASE

  # S3
  S3_ACCESS_KEY_ID
  S3_SECRET_ACCESS_KEY
  S3_ENDPOINT
  S3_BUCKET
  S3_REGION
  S3_SET_ACL
  S3_PUBLIC_DOMAIN
  S3_ENABLE_PATH_STYLE

  # SEARCH ENGINE
  CRAWLER_IMPLS # search1api,google,jina,exa,firecrawl,native
  SEARCH_PROVIDERS # search1api,google,jina,exa,firecrawl

  SEARCH1API_API_KEY
  SEARCH1API_CRAWL_API_KEY
  SEARCH1API_SEARCH_API_KEY

  EXA_API_KEY

  JINA_READER_API_KEY

  GOOGLE_PSE_API_KEY
  GOOGLE_PSE_ENGINE_ID

  FIRECRAWL_API_KEY

  TAVILY_API_KEY

  SEARXNG_URL

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

  HUNYUAN_API_KEY
  HUNYUAN_MODEL_LIST

  DEEPSEEK_PROXY_URL
  DEEPSEEK_API_KEY
  DEEPSEEK_MODEL_LIST

  ANTHROPIC_API_KEY
  ANTHROPIC_PROXY_URL

  AWS_ACCESS_KEY_ID
  AWS_SECRET_ACCESS_KEY
  AWS_REGION

  OPENROUTER_API_KEY
  OPENROUTER_MODEL_LIST

  TOGETHERAI_API_KEY
  TOGETHERAI_MODEL_LIST

  AIHUBMIX_API_KEY
  AIHUBMIX_MODEL_LIST

  GITHUB_TOKEN
  GITHUB_MODEL_LIST

  OLLAMA_PROXY_URL
  OLLAMA_MODEL_LIST

  MOONSHOT_API_KEY

  MINIMAX_API_KEY

  MISTRAL_API_KEY

  GROQ_API_KEY

  ZHIPU_API_KEY

  ZEROONE_API_KEY

  # SMTP
  SMTP_HOST
  SMTP_PORT
  SMTP_USER
  SMTP_PASS

  # Authorization
  ENABLE_OAUTH_SSO
  AUTH_SECRET
  JWKS_KEY
  AUTH_SSO_PROVIDERS
  AUTH_EMAIL_VERIFICATION
  AUTH_ALLOWED_EMAILS
  AUTH_DISABLE_EMAIL_PASSWORD
  INTERNAL_JWT_EXPIRATION # default 30s

  # https://lobehub.com/docs/self-hosting/advanced/sso-providers/microsoft-entra-id
  AUTH_AZURE_AD_ID
  AUTH_AZURE_AD_SECRET
  AUTH_AZURE_AD_TENANT_ID

  # https://lobehub.com/docs/self-hosting/advanced/sso-providers/github
  AUTH_GITHUB_ID
  AUTH_GITHUB_SECRET

  # Analytics
  ENABLE_GOOGLE_ANALYTICS
  GOOGLE_ANALYTICS_MEASUREMENT_ID

  AUTH_CLOUDFLARE_ZERO_TRUST_ID
  AUTH_CLOUDFLARE_ZERO_TRUST_SECRET
  AUTH_CLOUDFLARE_ZERO_TRUST_ISSUER

  AUTH_AUTHENTIK_ID
  AUTH_AUTHENTIK_SECRET
  AUTH_AUTHENTIK_ISSUER

  AUTH_LOGTO_ID
  AUTH_LOGTO_SECRET
  AUTH_LOGTO_ISSUER

  AUTH_CASDOOR_ID
  AUTH_CASDOOR_SECRET
  AUTH_CASDOOR_ISSUER

  AUTH_GENERIC_OIDC_ID
  AUTH_GENERIC_OIDC_SECRET
  AUTH_GENERIC_OIDC_ISSUER

  # Analytics
  GOOGLE_ANALYTICS_MEASUREMENT_ID
)

for TEST_ENV in "${LLM_LOBEHUB_TEST_ENV[@]}"; do
  TEST_ENV_KEY="LLM_LOBEHUB_${TEST_ENV}"
  if [[ ! -z "${!TEST_ENV_KEY}" ]]; then
    LLM_LOBEHUB_ENV+=(-e "$TEST_ENV=${!TEST_ENV_KEY}")
  fi
done

LLM_LOBEHUB_OPTIONS=()
LLM_LOBEHUB_HAS_HOST_NETWORK=0
if [[ ! -z "$LLM_LOBEHUB_NETWORK" ]]; then
  for network in ${LLM_LOBEHUB_NETWORK[@]}; do
    LLM_LOBEHUB_OPTIONS+=("--network=$network")
    if [[ $network == "host" ]]; then
      LLM_LOBEHUB_HAS_HOST_NETWORK=1
    fi
  done
fi
if [[ $LLM_LOBEHUB_HAS_HOST_NETWORK -eq 0 ]]; then
  LLM_LOBEHUB_OPTIONS+=(-p $LLM_LOBEHUB_PORT:$LLM_LOBEHUB_PORT)
fi

podman run -d --name llm-lobechat --security-opt label=disable \
  "${LLM_LOBEHUB_ENV[@]}" \
  "${LLM_LOBEHUB_OPTIONS[@]}" \
  $LLM_LOBECHAT_IMAGE_URL

if [[ $? -ne 0 ]]; then
  echo "Run llm-lobechat failed"
  exit 1
fi

if [[ "x$LLM_UPDATE" != "x" ]] || [[ "x$ROUTER_IMAGE_UPDATE" != "x" ]]; then
  podman image prune -a -f --filter "until=240h"
fi

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
