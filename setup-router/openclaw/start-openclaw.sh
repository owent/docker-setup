#!/bin/bash

# https://github.com/openclaw/openclaw
# https://docs.openclaw.ai/install/docker
# https://docs.openclaw.ai/install/podman
# https://docs.openclaw.ai/help/environment
# https://docs.openclaw.ai/gateway/security/index#reverse-proxy-configuration
# 特殊指令: https://docs.openclaw.ai/tools/slash-commands#command-list

# podman exec -it openclaw node openclaw.mjs agents add owent-dev
# podman exec -it openclaw node openclaw.mjs agents --help

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"

OPENCLAW_IMAGE_URL="${OPENCLAW_IMAGE_URL:-ghcr.io/openclaw/openclaw:slim}"

# 注意: dangerouslyDisableDeviceAuth: true 会导致pairing认证被禁用，要同时支持WebChat和其他IM只能把dmPolicy设置成open或allowlist+allowFrom
# OPENCLAW_NETWORK=(internal-frontend)
# OPENCLAW_ALLOWED_ORIGINS=https://your-allowed-origin.com,https://another-allowed-origin.com
# OPENCLAW_TRUSTED_PROXIES=127.0.0.1,10.0.0.0/8  # comma-separated, enables reverse proxy mode (loopback bind)
# OPENCLAW_LITELLM_BASE_URL=http://litellm-host:4000  # LiteLLM proxy endpoint (see https://docs.openclaw.ai/providers/litellm)
# OPENCLAW_GATEWAY_PASSWORD=
# # podman exec -it openclaw node openclaw.mjs config set gateway.auth.mode "password"
# # podman exec -it openclaw node openclaw.mjs config set gateway.auth.password "your-strong-password"

podman image inspect localhost/local_openclaw:latest > /dev/null 2>&1
if [[ $? -ne 0 ]] || [[ "x$OPENCLAW_UPDATE" != "x" ]] || [[ "x$ROUTER_IMAGE_UPDATE" != "x" ]]; then
  podman pull $OPENCLAW_IMAGE_URL
  if [[ $? -ne 0 ]]; then
    echo "Pull $OPENCLAW_IMAGE_URL failed"
    exit 1
  fi

  echo "FROM $OPENCLAW_IMAGE_URL

LABEL maintainer \"OWenT <admin@owent.net>\"

USER root
COPY ./image-base-install.sh /tmp/image-base-install.sh
COPY ./image-extra-install.sh /tmp/image-extra-install.sh
COPY ./nodejs-pkg-install.sh /tmp/nodejs-pkg-install.sh
RUN /bin/bash /tmp/image-base-install.sh
RUN /bin/bash /tmp/image-extra-install.sh

ENV PNPM_HOME=/app/pnpm PATH=/app/pnpm:\${PATH}
RUN /bin/bash /tmp/nodejs-pkg-install.sh

  " > "$SCRIPT_DIR/openclaw.Dockerfile"
  podman build \
    -t localhost/local_openclaw:latest \
    -v /usr/local/share/ca-certificates:/usr/local/share/ca-certificates,ro \
    -f "$SCRIPT_DIR/openclaw.Dockerfile" "$SCRIPT_DIR"

  if [[ $? -ne 0 ]]; then
    echo "Build localhost/local_openclaw:latest failed"
    exit 1
  fi
fi

# Default gateway port: https://docs.openclaw.ai/gateway/configuration-reference
if [[ -z "$OPENCLAW_PORT" ]]; then
  OPENCLAW_PORT=18789
fi

if [[ -z "$OPENCLAW_SHARED_COMPONENT_DIR" ]]; then
  OPENCLAW_SHARED_COMPONENT_DIR="$HOME/openclaw/shared"
fi

# State directory (config, credentials, sessions, .env)
# Maps to ~/.openclaw inside container (OPENCLAW_STATE_DIR)
if [[ -z "$OPENCLAW_ETC_DIR" ]]; then
  OPENCLAW_ETC_DIR="$HOME/openclaw/etc"
fi

# Extensions (Plugins) directory
# Maps to ~/.openclaw/extensions inside container
if [[ -z "$OPENCLAW_EXTENSIONS_DIR" ]]; then
  OPENCLAW_EXTENSIONS_DIR="$OPENCLAW_ETC_DIR/extensions"
fi

# Shared skills directory
# Maps to ~/.openclaw/skills inside container
if [[ -z "$OPENCLAW_SKILLS_DIR" ]]; then
  OPENCLAW_SKILLS_DIR="$OPENCLAW_SHARED_COMPONENT_DIR/skills"
fi

# user home directory
# Maps to ~/.local/share inside container
if [[ -z "$OPENCLAW_USER_HOME_LOCAL_SHARE_DIR" ]]; then
  OPENCLAW_USER_HOME_LOCAL_SHARE_DIR="$OPENCLAW_SHARED_COMPONENT_DIR/home/.local/share"
fi
# Maps to ~/.openclaw inside container
if [[ -z "$OPENCLAW_USER_HOME_OPENCLAW_DIR" ]]; then
  OPENCLAW_USER_HOME_OPENCLAW_DIR="$OPENCLAW_SHARED_COMPONENT_DIR/home/.openclaw"
fi

# Workspace (agent workspace data)
# Maps to ~/.openclaw/workspace inside container
if [[ -z "$OPENCLAW_DATA_DIR" ]]; then
  OPENCLAW_DATA_DIR="$HOME/openclaw/data"
fi

if [[ "root" == "$(id -un)" ]]; then
  SYSTEMD_SERVICE_DIR=/lib/systemd/system
  SYSTEMD_CONTAINER_DIR=/etc/containers/systemd/
  mkdir -p "$SYSTEMD_CONTAINER_DIR"
else
  SYSTEMD_SERVICE_DIR="$HOME/.config/systemd/user"
  SYSTEMD_CONTAINER_DIR="$HOME/.config/containers/systemd"
  mkdir -p "$SYSTEMD_SERVICE_DIR"
  mkdir -p "$SYSTEMD_CONTAINER_DIR"
fi

mkdir -p "$OPENCLAW_ETC_DIR"
mkdir -p "$OPENCLAW_ETC_DIR/canvas"
mkdir -p "$OPENCLAW_ETC_DIR/cron"
mkdir -p "$OPENCLAW_ETC_DIR/devices"
mkdir -p "$OPENCLAW_EXTENSIONS_DIR"
mkdir -p "$OPENCLAW_SKILLS_DIR"
mkdir -p "$OPENCLAW_USER_HOME_LOCAL_SHARE_DIR"
mkdir -p "$OPENCLAW_USER_HOME_OPENCLAW_DIR"
mkdir -p "$OPENCLAW_DATA_DIR/default"

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

  # Build gateway.auth block when OPENCLAW_GATEWAY_PASSWORD is set
  # This ensures password mode persists in config across pod recreation
  OPENCLAW_GATEWAY_AUTH_BLOCK=""
  if [[ -n "$OPENCLAW_GATEWAY_PASSWORD" ]]; then
    OPENCLAW_GATEWAY_AUTH_BLOCK=",
    \"auth\": {
      \"mode\": \"password\",
      \"password\": \"${OPENCLAW_GATEWAY_PASSWORD}\"
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
    "bind": "${OPENCLAW_GATEWAY_BIND}"${OPENCLAW_GATEWAY_AUTH_BLOCK}${OPENCLAW_TRUSTED_PROXIES_BLOCK}${OPENCLAW_CONTROL_UI_BLOCK}
  },
  "skills": {
    "load": {
      "extraDirs": [
        "/openclaw/skills"
      ],
      "watch": true 
    },
    "install": {
      "nodeManager": "bun"
    }
  },
  "canvasHost": {
    "root": "/openclaw/etc/canvas"
  },
  "agents": {
    "defaults": {
      "workspace": "/openclaw/data/default"
    }
  }${OPENCLAW_MODELS_BLOCK}
}
EOF
fi

# Update gateway.auth in existing config when OPENCLAW_GATEWAY_PASSWORD is set
# This prevents auth mode from reverting to "token" on pod recreation
if [[ -n "$OPENCLAW_GATEWAY_PASSWORD" ]] && [[ -e "$OPENCLAW_ETC_DIR/openclaw.json" ]]; then
  if command -v python3 >/dev/null 2>&1; then
    python3 -c "
import json, sys
with open(sys.argv[1], 'r') as f:
    config = json.load(f)
config.setdefault('gateway', {})['auth'] = {'mode': 'password', 'password': sys.argv[2]}
with open(sys.argv[1], 'w') as f:
    json.dump(config, f, indent=2)
    f.write('\\n')
" "$OPENCLAW_ETC_DIR/openclaw.json" "$OPENCLAW_GATEWAY_PASSWORD"
  elif command -v jq >/dev/null 2>&1; then
    OPENCLAW_TMP_JSON="$(jq --arg pw "$OPENCLAW_GATEWAY_PASSWORD" '.gateway.auth = {"mode": "password", "password": $pw}' \
      "$OPENCLAW_ETC_DIR/openclaw.json")"
    if [[ $? -eq 0 ]] && [[ -n "$OPENCLAW_TMP_JSON" ]]; then
      echo "$OPENCLAW_TMP_JSON" >"$OPENCLAW_ETC_DIR/openclaw.json"
    fi
  else
    echo "WARNING: OPENCLAW_GATEWAY_PASSWORD is set but cannot update existing config (need python3 or jq)."
    echo "         Run manually: podman exec -it openclaw node openclaw.mjs config set gateway.auth.mode password"
  fi
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
  # -e NODE_EXTRA_CA_CERTS=/etc/ssl/certs/ca-certificates.crt
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
#   etc dir          → /openclaw/etc             (state: config, credentials, sessions, .env)
#   extensions dir   → /openclaw/etc/extensions  (plugins and extensions)
#   data dir         → /openclaw/data            (agent workspace, set via agents.defaults.workspace)
OPENCLAW_OPTIONS=(
  --mount type=bind,source=$OPENCLAW_ETC_DIR,target=/openclaw/etc
  --mount type=bind,source=$OPENCLAW_EXTENSIONS_DIR,target=/openclaw/etc/extensions
  --mount type=bind,source=$OPENCLAW_SKILLS_DIR,target=/openclaw/skills
  --mount type=bind,source=$OPENCLAW_DATA_DIR,target=/openclaw/data
  --mount type=bind,source=$OPENCLAW_USER_HOME_LOCAL_SHARE_DIR,target=/root/.local/share
  --mount type=bind,source=$OPENCLAW_USER_HOME_OPENCLAW_DIR,target=/root/.openclaw
  --mount type=bind,source=/etc/ssl/certs/,target=/etc/ssl/certs/,ro
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

PODLET_IMAGE_URL="ghcr.io/containers/podlet:latest"
PODLET_RUN=($(which podlet 2>/dev/null))
FIND_PODLET_RESULT=$?
if [[ $FIND_PODLET_RESULT -ne 0 ]]; then
  (podman image inspect "$PODLET_IMAGE_URL" > /dev/null 2>&1 || podman pull "$PODLET_IMAGE_URL") && FIND_PODLET_RESULT=0 && PODLET_RUN=(podman run --rm "$PODLET_IMAGE_URL")
fi

if [[ $FIND_PODLET_RESULT -eq 0 ]]; then
  ${PODLET_RUN[@]} --install --wanted-by default.target --wants network-online.target --after network-online.target \
    podman run -d --name openclaw --security-opt label=disable --user root \
    "${OPENCLAW_ENV[@]}" "${OPENCLAW_OPTIONS[@]}" \
    localhost/local_openclaw:latest \
    node openclaw.mjs gateway --allow-unconfigured --bind lan --port $OPENCLAW_PORT \
    | tee -p "$SYSTEMD_CONTAINER_DIR/openclaw.container"
else
  podman run -d --name openclaw --security-opt label=disable --user root \
    "${OPENCLAW_ENV[@]}" "${OPENCLAW_OPTIONS[@]}" \
    localhost/local_openclaw:latest \
    node openclaw.mjs gateway --allow-unconfigured --bind lan --port $OPENCLAW_PORT

  if [[ $? -ne 0 ]]; then
    echo "Run openclaw failed"
    exit 1
  fi
  podman generate systemd openclaw | tee -p "$SYSTEMD_SERVICE_DIR/openclaw.service"
  podman container stop openclaw
fi

if [[ "$SYSTEMD_SERVICE_DIR" == "/lib/systemd/system" ]]; then
  systemctl daemon-reload
else
  systemctl --user daemon-reload
fi

if [[ "$SYSTEMD_SERVICE_DIR" == "/lib/systemd/system" ]]; then
  if [[ $FIND_PODLET_RESULT -ne 0 ]]; then
    systemctl enable openclaw.service
  fi
  systemctl start openclaw.service
else
  if [[ $FIND_PODLET_RESULT -ne 0 ]]; then
    systemctl --user enable openclaw.service
  fi
  systemctl --user start openclaw.service
fi

# podman cp /usr/local/share/ca-certificates/* openclaw:/usr/local/share/ca-certificates/
# podman exec openclaw update-ca-certificates


echo "============================================="
echo "OpenClaw gateway started on port $OPENCLAW_PORT"
echo "Control UI: http://127.0.0.1:$OPENCLAW_PORT/"
echo "Config dir: $OPENCLAW_ETC_DIR"
echo "Extensions: $OPENCLAW_EXTENSIONS_DIR"
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
# ====================================== Plugins (Extensions) ==============================
# Manage plugins loaded in-process (e.g., Voice Call, external tools/handlers):
#   podman exec -it openclaw node openclaw.mjs plugins list
#   podman exec -it openclaw node openclaw.mjs plugins install @openclaw/voice-call
#   podman exec -it openclaw node openclaw.mjs plugins uninstall <id>
#   podman exec -it openclaw node openclaw.mjs plugins enable <id>
#   podman exec -it openclaw node openclaw.mjs plugins update --all
# Note: npm specs are registry-only. Dependency installs run with --ignore-scripts.
# Configs for plugins go into openclaw.json under plugins.entries.<id>.config.
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
# 添加 agent
#   podman exec -it openclaw node openclaw.mjs agents add --agent-dir /openclaw/data/NAME/agent  --workspace /openclaw/data/NAME/workspace NAME
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