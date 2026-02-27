#!/bin/bash

# https://github.com/openclaw/openclaw
# https://docs.openclaw.ai/install/docker
# https://docs.openclaw.ai/install/podman
# https://docs.openclaw.ai/help/environment
# https://docs.openclaw.ai/gateway/security/index#reverse-proxy-configuration

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"

OPENCLAW_IMAGE_URL="${OPENCLAW_IMAGE_URL:-ghcr.io/openclaw/openclaw:latest}"

# OPENCLAW_NETWORK=(internal-frontend)
# OPENCLAW_ALLOWED_ORIGINS=https://your-allowed-origin.com,https://another-allowed-origin.com
# OPENCLAW_TRUSTED_PROXIES=127.0.0.1,10.0.0.0/8  # comma-separated, enables reverse proxy mode (loopback bind)
# OPENCLAW_LITELLM_BASE_URL=http://litellm-host:4000  # LiteLLM proxy endpoint (see https://docs.openclaw.ai/providers/litellm)
# OPENCLAW_GATEWAY_PASSWORD=
# # podman exec -it openclaw node openclaw.mjs config set gateway.auth.mode "password"
# # podman exec -it openclaw node openclaw.mjs config set gateway.auth.password "your-strong-password"

if [[ "x$OPENCLAW_UPDATE" != "x" ]] || [[ "x$ROUTER_IMAGE_UPDATE" != "x" ]]; then
  podman pull $OPENCLAW_IMAGE_URL
  if [[ $? -ne 0 ]]; then
    echo "Pull $OPENCLAW_IMAGE_URL failed"
    exit 1
  fi
fi

# Default gateway port: https://docs.openclaw.ai/gateway/configuration-reference
if [[ -z "$OPENCLAW_PORT" ]]; then
  OPENCLAW_PORT=18789
fi

# State directory (config, credentials, sessions, .env)
# Maps to ~/.openclaw inside container (OPENCLAW_STATE_DIR)
if [[ -z "$OPENCLAW_ETC_DIR" ]]; then
  OPENCLAW_ETC_DIR="$HOME/openclaw/etc"
fi

# Workspace (agent workspace data)
# Maps to ~/.openclaw/workspace inside container
if [[ -z "$OPENCLAW_DATA_DIR" ]]; then
  OPENCLAW_DATA_DIR="$HOME/openclaw/data"
fi

mkdir -p "$OPENCLAW_ETC_DIR"
mkdir -p "$OPENCLAW_ETC_DIR/canvas"
mkdir -p "$OPENCLAW_ETC_DIR/cron"
mkdir -p "$OPENCLAW_ETC_DIR/devices"
mkdir -p "$OPENCLAW_DATA_DIR"

# Create minimal config if not present so gateway can start without the wizard
# See https://docs.openclaw.ai/install/podman
# agents.defaults.workspace sets the agent workspace directory
if [[ ! -e "$OPENCLAW_ETC_DIR/openclaw.json" ]]; then
  # Build models.providers block for custom base URLs (only applied on initial config creation)
  # OPENCLAW_OPENAI_BASE_URL:   custom OpenAI-compatible proxy endpoint (e.g. https://your-proxy.example.com/v1)
  # OPENCLAW_ZAI_BASE_URL:      custom Z.AI/智谱 endpoint (e.g. https://open.bigmodel.cn/api/paas/v4)
  # OPENCLAW_LITELLM_BASE_URL:  LiteLLM proxy endpoint (e.g. http://localhost:4000)
  #   See https://docs.openclaw.ai/providers/litellm
  # See https://docs.openclaw.ai/gateway/configuration-reference#custom-providers-and-base-urls
  OPENCLAW_MODELS_BLOCK=""
  if [[ -n "$OPENCLAW_OPENAI_BASE_URL" ]] || [[ -n "$OPENCLAW_ZAI_BASE_URL" ]] || [[ -n "$OPENCLAW_LITELLM_BASE_URL" ]]; then
    OPENCLAW_PROVIDER_ENTRIES=""
    OPENCLAW_ENTRY_SEP=""
    if [[ -n "$OPENCLAW_OPENAI_BASE_URL" ]]; then
      OPENCLAW_PROVIDER_ENTRIES+="      \"openai\": {
        \"baseUrl\": \"${OPENCLAW_OPENAI_BASE_URL}\",
        \"api\": \"openai-completions\",
        \"models\": []
      }"
      OPENCLAW_ENTRY_SEP=",
"
    fi
    if [[ -n "$OPENCLAW_ZAI_BASE_URL" ]]; then
      OPENCLAW_PROVIDER_ENTRIES+="${OPENCLAW_ENTRY_SEP}      \"zai\": {
        \"baseUrl\": \"${OPENCLAW_ZAI_BASE_URL}\",
        \"api\": \"openai-completions\",
        \"models\": []
      }"
      OPENCLAW_ENTRY_SEP=",
"
    fi
    if [[ -n "$OPENCLAW_LITELLM_BASE_URL" ]]; then
      OPENCLAW_PROVIDER_ENTRIES+="${OPENCLAW_ENTRY_SEP}      \"litellm\": {
        \"baseUrl\": \"${OPENCLAW_LITELLM_BASE_URL}\",
        \"api\": \"openai-completions\",
        \"models\": []
      }"
    fi
    OPENCLAW_MODELS_BLOCK=",
  \"models\": {
    \"providers\": {
${OPENCLAW_PROVIDER_ENTRIES}
    }
  }"
  fi

  # Build controlUi block
  # OPENCLAW_ALLOWED_ORIGINS: comma-separated list of allowed origins (e.g. https://openclaw.example.com,https://other.example.com)
  # If not set, falls back to dangerouslyAllowHostHeaderOriginFallback for convenience
  #
  # Reverse proxy mode (OPENCLAW_TRUSTED_PROXIES):
  #   When set, gateway binds to loopback and trusts proxy headers from listed IPs.
  #   OPENCLAW_ALLOWED_ORIGINS should be set to the HTTPS origin(s) of your proxy domain.
  #   See https://docs.openclaw.ai/gateway/security/index#reverse-proxy-configuration
  #   See https://docs.openclaw.ai/gateway/trusted-proxy-auth
  OPENCLAW_CONTROL_UI_BLOCK=""
  OPENCLAW_GATEWAY_BIND="lan"
  OPENCLAW_TRUSTED_PROXIES_BLOCK=""

  # Build trustedProxies block if OPENCLAW_TRUSTED_PROXIES is set
  if [[ -n "$OPENCLAW_TRUSTED_PROXIES" ]]; then
    OPENCLAW_GATEWAY_BIND="loopback"
    OPENCLAW_PROXIES_JSON=""
    OPENCLAW_PROXIES_SEP=""
    IFS=',' read -ra OPENCLAW_PROXIES_ARRAY <<< "$OPENCLAW_TRUSTED_PROXIES"
    for proxy_ip in "${OPENCLAW_PROXIES_ARRAY[@]}"; do
      proxy_ip="$(echo "$proxy_ip" | xargs)" # trim whitespace
      OPENCLAW_PROXIES_JSON+="${OPENCLAW_PROXIES_SEP}\"${proxy_ip}\""
      OPENCLAW_PROXIES_SEP=", "
    done
    OPENCLAW_TRUSTED_PROXIES_BLOCK=",
    \"trustedProxies\": [${OPENCLAW_PROXIES_JSON}]"
  fi

  if [[ -n "$OPENCLAW_ALLOWED_ORIGINS" ]]; then
    # Convert comma-separated origins to JSON array
    OPENCLAW_ORIGINS_JSON=""
    OPENCLAW_ORIGINS_SEP=""
    IFS=',' read -ra OPENCLAW_ORIGINS_ARRAY <<< "$OPENCLAW_ALLOWED_ORIGINS"
    for origin in "${OPENCLAW_ORIGINS_ARRAY[@]}"; do
      origin="$(echo "$origin" | xargs)" # trim whitespace
      OPENCLAW_ORIGINS_JSON+="${OPENCLAW_ORIGINS_SEP}\"${origin}\""
      OPENCLAW_ORIGINS_SEP=", "
    done
    if [[ -n "$OPENCLAW_TRUSTED_PROXIES" ]]; then
      # Behind reverse proxy with HTTPS — no insecure flags needed
      # dangerouslyDisableDeviceAuth: device pairing is not needed when proxy handles auth boundary
      OPENCLAW_CONTROL_UI_BLOCK=",
    \"controlUi\": {
      \"allowedOrigins\": [${OPENCLAW_ORIGINS_JSON}],
      \"dangerouslyDisableDeviceAuth\": true
    }"
    else
      # Direct HTTP access — need allowInsecureAuth for non-loopback
      OPENCLAW_CONTROL_UI_BLOCK=",
    \"controlUi\": {
      \"allowedOrigins\": [${OPENCLAW_ORIGINS_JSON}],
      \"allowInsecureAuth\": true
    }"
    fi
  else
    if [[ -n "$OPENCLAW_TRUSTED_PROXIES" ]]; then
      echo "WARNING: OPENCLAW_TRUSTED_PROXIES is set but OPENCLAW_ALLOWED_ORIGINS is not."
      echo "         You should set OPENCLAW_ALLOWED_ORIGINS to your proxy's HTTPS origin(s)."
      echo "         e.g. OPENCLAW_ALLOWED_ORIGINS=https://openclaw.example.com"
      # Fallback for reverse proxy without explicit origins
      OPENCLAW_CONTROL_UI_BLOCK=",
    \"controlUi\": {
      \"dangerouslyAllowHostHeaderOriginFallback\": true,
      \"dangerouslyDisableDeviceAuth\": true
    }"
    else
      # Direct access without explicit origins — use dangerous fallback + insecure auth
      OPENCLAW_CONTROL_UI_BLOCK=",
    \"controlUi\": {
      \"dangerouslyAllowHostHeaderOriginFallback\": true,
      \"allowInsecureAuth\": true
    }"
    fi
  fi

  cat >"$OPENCLAW_ETC_DIR/openclaw.json" <<EOF
{
  "gateway": {
    "mode": "local",
    "port": 18789,
    "bind": "${OPENCLAW_GATEWAY_BIND}"${OPENCLAW_TRUSTED_PROXIES_BLOCK}${OPENCLAW_CONTROL_UI_BLOCK}
  },
  "canvasHost": {
    "root": "/openclaw/etc/canvas"
  },
  "agents": {
    "defaults": {
      "workspace": "/openclaw/data"
    }
  }${OPENCLAW_MODELS_BLOCK}
}
EOF
fi

# ====================================== start deploy ======================================
if [[ "root" == "$(id -un)" ]]; then
  SYSTEMD_SERVICE_DIR=/lib/systemd/system
else
  SYSTEMD_SERVICE_DIR="$HOME/.config/systemd/user"
  mkdir -p "$SYSTEMD_SERVICE_DIR"
fi

if [[ "$SYSTEMD_SERVICE_DIR" == "/lib/systemd/system" ]]; then
  systemctl --all | grep -F openclaw.service >/dev/null 2>&1
  if [ $? -eq 0 ]; then
    systemctl stop openclaw.service
    systemctl disable openclaw.service
  fi
else
  export XDG_RUNTIME_DIR="/run/user/$UID"
  export DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR}/bus"

  # Maybe need run from host: loginctl enable-linger tools
  # see https://wiki.archlinux.org/index.php/Systemd/User
  # sudo loginctl enable-linger $RUN_USER
  systemctl --user --all | grep -F openclaw.service >/dev/null 2>&1
  if [ $? -eq 0 ]; then
    systemctl --user stop openclaw.service
    systemctl --user disable openclaw.service
  fi
fi

podman container inspect openclaw >/dev/null 2>&1

if [[ $? -eq 0 ]]; then
  podman stop openclaw
  podman rm -f openclaw
fi

if [[ "x$OPENCLAW_UPDATE" != "x" ]] || [[ "x$ROUTER_IMAGE_UPDATE" != "x" ]]; then
  podman image prune -a -f --filter "until=240h"
fi

OPENCLAW_ENV=(
  -e TZ=Asia/Shanghai
)

# Authentication: OPENCLAW_GATEWAY_PASSWORD (optional)
if [[ ! -z "$OPENCLAW_GATEWAY_PASSWORD" ]]; then
  OPENCLAW_ENV+=(-e OPENCLAW_GATEWAY_PASSWORD="$OPENCLAW_GATEWAY_PASSWORD")
else
  # Authentication: OPENCLAW_GATEWAY_TOKEN
  # See https://docs.openclaw.ai/gateway/configuration-reference (gateway.auth)
  if [[ -e "$SCRIPT_DIR/openclaw.GATEWAY_TOKEN" ]]; then
    OPENCLAW_GATEWAY_TOKEN="$(cat "$SCRIPT_DIR/openclaw.GATEWAY_TOKEN")"
  elif [[ -e "$OPENCLAW_ETC_DIR/.env" ]] && grep -q '^OPENCLAW_GATEWAY_TOKEN=' "$OPENCLAW_ETC_DIR/.env" 2>/dev/null; then
    OPENCLAW_GATEWAY_TOKEN="$(grep '^OPENCLAW_GATEWAY_TOKEN=' "$OPENCLAW_ETC_DIR/.env" | head -1 | cut -d= -f2-)"
  else
    OPENCLAW_GATEWAY_TOKEN="$(head -c 24 /dev/urandom | base64 | tr '/' '_' | tr '+' '-')"
    echo "$OPENCLAW_GATEWAY_TOKEN" >"$SCRIPT_DIR/openclaw.GATEWAY_TOKEN"
  fi
  OPENCLAW_ENV+=(-e OPENCLAW_GATEWAY_TOKEN="$OPENCLAW_GATEWAY_TOKEN")
fi

# Path env vars: https://docs.openclaw.ai/help/environment
# OPENCLAW_STATE_DIR overrides state directory (default ~/.openclaw)
# OPENCLAW_CONFIG_PATH overrides config file path (default ~/.openclaw/openclaw.json)
OPENCLAW_ENV+=(
  -e OPENCLAW_STATE_DIR=/openclaw/etc
  -e OPENCLAW_CONFIG_PATH=/openclaw/etc/openclaw.json
)

# Provider API keys
# See https://docs.openclaw.ai/gateway/configuration-reference (env, models)
# OPENROUTER_API_KEY
if [[ ! -z "$OPENCLAW_OPENROUTER_API_KEY" ]]; then
  OPENCLAW_ENV+=(-e OPENROUTER_API_KEY="$OPENCLAW_OPENROUTER_API_KEY")
fi

# ANTHROPIC_API_KEY
if [[ ! -z "$OPENCLAW_ANTHROPIC_API_KEY" ]]; then
  OPENCLAW_ENV+=(-e ANTHROPIC_API_KEY="$OPENCLAW_ANTHROPIC_API_KEY")
fi

# OPENAI_API_KEY
if [[ ! -z "$OPENCLAW_OPENAI_API_KEY" ]]; then
  OPENCLAW_ENV+=(-e OPENAI_API_KEY="$OPENCLAW_OPENAI_API_KEY")
fi

# ZAI_API_KEY (Z.AI / GLM)
if [[ ! -z "$OPENCLAW_ZAI_API_KEY" ]]; then
  OPENCLAW_ENV+=(-e ZAI_API_KEY="$OPENCLAW_ZAI_API_KEY")
fi

# GROQ_API_KEY
if [[ ! -z "$OPENCLAW_GROQ_API_KEY" ]]; then
  OPENCLAW_ENV+=(-e GROQ_API_KEY="$OPENCLAW_GROQ_API_KEY")
fi

# GOOGLE_API_KEY (Gemini)
if [[ ! -z "$OPENCLAW_GOOGLE_API_KEY" ]]; then
  OPENCLAW_ENV+=(-e GOOGLE_API_KEY="$OPENCLAW_GOOGLE_API_KEY")
fi

# LITELLM_API_KEY (LiteLLM proxy)
# See https://docs.openclaw.ai/providers/litellm
if [[ ! -z "$OPENCLAW_LITELLM_API_KEY" ]]; then
  OPENCLAW_ENV+=(-e LITELLM_API_KEY="$OPENCLAW_LITELLM_API_KEY")
fi

# Channel tokens (optional, can also be set in openclaw.json)
# TELEGRAM_BOT_TOKEN
if [[ ! -z "$OPENCLAW_TELEGRAM_BOT_TOKEN" ]]; then
  OPENCLAW_ENV+=(-e TELEGRAM_BOT_TOKEN="$OPENCLAW_TELEGRAM_BOT_TOKEN")
fi

# DISCORD_BOT_TOKEN
if [[ ! -z "$OPENCLAW_DISCORD_BOT_TOKEN" ]]; then
  OPENCLAW_ENV+=(-e DISCORD_BOT_TOKEN="$OPENCLAW_DISCORD_BOT_TOKEN")
fi

# Logging: OPENCLAW_LOG_LEVEL (debug, info, warn, error, trace)
if [[ ! -z "$OPENCLAW_LOG_LEVEL" ]]; then
  OPENCLAW_ENV+=(-e OPENCLAW_LOG_LEVEL="$OPENCLAW_LOG_LEVEL")
fi

# Container volume mounts:
#   etc dir  → /openclaw/etc   (state: config, credentials, sessions, .env)
#   data dir → /openclaw/data  (agent workspace, set via agents.defaults.workspace)
OPENCLAW_OPTIONS=(
  --mount type=bind,source=$OPENCLAW_ETC_DIR,target=/openclaw/etc
  --mount type=bind,source=$OPENCLAW_DATA_DIR,target=/openclaw/data
)

OPENCLAW_HAS_HOST_NETWORK=0
if [[ ! -z "$OPENCLAW_NETWORK" ]]; then
  for network in ${OPENCLAW_NETWORK[@]}; do
    OPENCLAW_OPTIONS+=("--network=$network")
    if [[ $network == "host" ]]; then
      OPENCLAW_HAS_HOST_NETWORK=1
    fi
  done
fi
if [[ $OPENCLAW_HAS_HOST_NETWORK -eq 0 ]]; then
  OPENCLAW_OPTIONS+=(-p $OPENCLAW_PORT:$OPENCLAW_PORT)
fi

# Container default CMD binds to loopback; override with --bind lan for container access
# See https://docs.openclaw.ai/install/docker
# --user root: the default image runs as 'node' (uid 1000) which cannot write to
#   host-mounted directories under podman rootless uid mapping. Running as root
#   inside the container avoids EACCES on /openclaw/etc subdirs (cron, devices, etc).
podman run -d --name openclaw --security-opt label=disable --user root \
  "${OPENCLAW_ENV[@]}" "${OPENCLAW_OPTIONS[@]}" \
  $OPENCLAW_IMAGE_URL \
  node openclaw.mjs gateway --allow-unconfigured --bind lan --port $OPENCLAW_PORT

if [[ $? -ne 0 ]]; then
  echo "Run openclaw failed"
  exit 1
fi

podman generate systemd openclaw | tee -p "$SYSTEMD_SERVICE_DIR/openclaw.service"
# OpenClaw does "full process restart" on config changes (e.g. models auth paste-token),
# which exits PID 1 and stops the container. Restart=always ensures systemd brings it back.
sed -i 's/^Restart=.*$/Restart=always/' "$SYSTEMD_SERVICE_DIR/openclaw.service"
if ! grep -q '^RestartSec=' "$SYSTEMD_SERVICE_DIR/openclaw.service"; then
  sed -i '/^Restart=always$/a RestartSec=3' "$SYSTEMD_SERVICE_DIR/openclaw.service"
fi
podman container stop openclaw

if [[ "$SYSTEMD_SERVICE_DIR" == "/lib/systemd/system" ]]; then
  systemctl enable openclaw.service
  systemctl daemon-reload
  systemctl start openclaw.service
else
  systemctl --user enable "$SYSTEMD_SERVICE_DIR/openclaw.service"
  systemctl --user daemon-reload
  systemctl --user start openclaw.service
fi

echo "============================================="
echo "OpenClaw gateway started on port $OPENCLAW_PORT"
echo "Control UI: http://127.0.0.1:$OPENCLAW_PORT/"
echo "Config dir: $OPENCLAW_ETC_DIR"
echo "Workspace:  $OPENCLAW_DATA_DIR"
echo "============================================="

# ====================================== Usage ======================================
# Start:  systemctl [--user] start openclaw.service
# Stop:   systemctl [--user] stop openclaw.service
# Status: systemctl [--user] status openclaw.service
# Logs:   journalctl [--user] -u openclaw.service -f
#
# Control UI: http://127.0.0.1:18789/
# CLI inside container (use 'node openclaw.mjs' instead of 'openclaw'):
#   podman exec -it openclaw node openclaw.mjs onboard
#   podman exec openclaw node openclaw.mjs doctor
#   podman exec openclaw node openclaw.mjs security audit
#   podman exec openclaw node openclaw.mjs dashboard
#   podman exec openclaw node openclaw.mjs dashboard --no-open
#
# ====================================== Reverse Proxy (Caddy) ====================
# See openclaw.Caddyfile.location for Caddy reverse proxy configuration.
#
# Required env vars for reverse proxy mode:
#   OPENCLAW_TRUSTED_PROXIES=127.0.0.1
#   OPENCLAW_ALLOWED_ORIGINS=https://openclaw.example.com
#   OPENCLAW_GATEWAY_PASSWORD=your-strong-password
#
# The gateway will bind to loopback and trust proxy headers from OPENCLAW_TRUSTED_PROXIES.
# Caddy handles TLS termination, HSTS, and WebSocket upgrade.
# See https://docs.openclaw.ai/gateway/security/index#reverse-proxy-configuration
#
# ====================================== Model Auth ======================================
# Interactive auth wizard (prompts for provider + credentials, creates api_key profile):
#   podman exec -it openclaw node openclaw.mjs models auth add
# # 非交互式添加 OpenRouter API key
#   podman exec -it openclaw node openclaw.mjs onboard --non-interactive --accept-risk \
#     --auth-choice openrouter-api-key --openrouter-api-key "sk-or-v1-..."
# 
# # 非交互式添加 OpenAI API key
#   podman exec -it openclaw node openclaw.mjs onboard --non-interactive --accept-risk \
#     --auth-choice openai-api-key --openai-api-key "sk-..."
#
# # 非交互式添加 LiteLLM API key
#   podman exec -it openclaw node openclaw.mjs onboard --non-interactive --accept-risk \
#     --auth-choice litellm-api-key --litellm-api-key "sk-..."
#
# NOTE: 'paste-token' is for OAuth/session tokens only (creates mode:"token" profile).
#       For API keys, use 'models auth add' interactively, or pass keys via env vars
#       (OPENCLAW_OPENAI_API_KEY, OPENCLAW_OPENROUTER_API_KEY, etc.) in this script.
#
# Paste OAuth token for a specific provider (NOT for API keys):
#   podman exec -it openclaw node openclaw.mjs models auth paste-token --provider anthropic
#
# Setup token (OAuth flow, default anthropic):
#   podman exec -it openclaw node openclaw.mjs models auth setup-token --provider anthropic
#
# Set default model:
#   podman exec -it openclaw node openclaw.mjs models set "zai/glm-5"
#   podman exec -it openclaw node openclaw.mjs config set agents.defaults.model '{"primary":"zai/glm-5","fallbacks":["openrouter/google/gemini-3.1-pro-preview","litellm/gemini-3.1-pro-preview","litellm/gpt-5.2","litellm/claude-sonnet-4.6","openrouter/openai/gpt-5.2"]}'
#
# Scan models from a specific provider:
#   podman exec -it openclaw node openclaw.mjs models scan --provider openrouter
#   podman exec -it openclaw node openclaw.mjs models scan --provider zai
#   podman exec -it openclaw node openclaw.mjs models scan --provider litellm
#   podman exec -it openclaw node openclaw.mjs models scan --provider openai
# # 列出 openrouter 所有可用模型
#   podman exec -it openclaw node openclaw.mjs models list --all --provider openrouter
#
# # 直接设置你想用的模型（不需要 scan）
#   podman exec -it openclaw node openclaw.mjs models set "openrouter/anthropic/claude-sonnet-4"
#
# Check model/auth status:
#   podman exec -it openclaw node openclaw.mjs models status
#
# Remove a misconfigured auth profile:
#   podman exec -it openclaw node openclaw.mjs config unset auth.profiles.openai:manual
#
# ====================================== LiteLLM ======================================
# LiteLLM is an open-source LLM gateway for unified model routing + cost tracking.
# See https://docs.openclaw.ai/providers/litellm
#
# Env vars for LiteLLM:
#   OPENCLAW_LITELLM_BASE_URL=http://litellm-host:4000
#   OPENCLAW_LITELLM_API_KEY=sk-litellm-key
#
# 同步 LiteLLM 模型列表到 OpenClaw（查询 /model/info 或 /v1/models，需要 jq）:
#   OPENCLAW_LITELLM_BASE_URL=http://litellm-host:4000 \
#     OPENCLAW_LITELLM_API_KEY=sk-litellm-key \
#     bash update-litellm-models.sh
#
# After deploy, set default model to a LiteLLM-routed model:
#   podman exec -it openclaw node openclaw.mjs models set "litellm/claude-opus-4-6"