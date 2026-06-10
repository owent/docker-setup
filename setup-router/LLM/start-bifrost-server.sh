#!/bin/bash
set -e

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
SERVICE_NAME="llm-bifrost"
PODLET_IMAGE_URL=${PODLET_IMAGE_URL:-"ghcr.io/containers/podlet:latest"}

if [[ "root" == "$(id -un)" ]]; then
  SYSTEMD_SERVICE_DIR=/lib/systemd/system
  SYSTEMD_CONTAINER_DIR=/etc/containers/systemd
  SYSTEMCTL=(systemctl)
  DEFAULT_BIFROST_DATA_DIR=/var/lib/llm/bifrost/data
else
  SYSTEMD_SERVICE_DIR="$HOME/.config/systemd/user"
  SYSTEMD_CONTAINER_DIR="$HOME/.config/containers/systemd"
  SYSTEMCTL=(systemctl --user)
  DEFAULT_BIFROST_DATA_DIR="$HOME/llm/bifrost/data"
  export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$UID}"
  export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=${XDG_RUNTIME_DIR}/bus}"
fi

mkdir -p "$SYSTEMD_SERVICE_DIR"
mkdir -p "$SYSTEMD_CONTAINER_DIR"

LLM_BIFROST_IMAGE_URL=${LLM_BIFROST_IMAGE_URL:-"docker.io/maximhq/bifrost:latest"}
LLM_BIFROST_PORT=${LLM_BIFROST_PORT:-8080}
LLM_BIFROST_DATA_DIR=${LLM_BIFROST_DATA_DIR:-"$DEFAULT_BIFROST_DATA_DIR"}
LLM_BIFROST_CONFIG_FILE=${LLM_BIFROST_CONFIG_FILE:-"$LLM_BIFROST_DATA_DIR/config.json"}
LLM_BIFROST_CONFIG_TEMPLATE=${LLM_BIFROST_CONFIG_TEMPLATE:-"$SCRIPT_DIR/bifrost-config.postgres-s3.template.json"}

mkdir -p "$LLM_BIFROST_DATA_DIR"

if [[ -n "${LLM_UPDATE:-}" || -n "${ROUTER_IMAGE_UPDATE:-}" ]]; then
  podman pull "$LLM_BIFROST_IMAGE_URL"
fi

if [[ ! -e "$LLM_BIFROST_CONFIG_FILE" ]]; then
  echo "Bifrost config file is missing: $LLM_BIFROST_CONFIG_FILE"
  echo "Copy and edit the template first, for example:"
  echo "  cp \"$LLM_BIFROST_CONFIG_TEMPLATE\" \"$LLM_BIFROST_CONFIG_FILE\""
  exit 1
fi

SECRET_DIR="$LLM_BIFROST_DATA_DIR/secrets"
ENCRYPTION_KEY_FILE="$SECRET_DIR/BIFROST_ENCRYPTION_KEY"
ADMIN_PASSWORD_FILE="$SECRET_DIR/ADMIN_PASSWORD"
BIFROST_ADMIN_PASSWORD_SOURCE="$ADMIN_PASSWORD_FILE"
mkdir -p "$SECRET_DIR"

if [[ -n "${LLM_BIFROST_ADMIN_PASSWORD:-}" ]]; then
  BIFROST_ADMIN_PASSWORD_SOURCE="environment variable"
fi
if [[ -z "${LLM_BIFROST_ENCRYPTION_KEY:-}" && ! -e "$ENCRYPTION_KEY_FILE" ]]; then
  openssl rand -hex 32 > "$ENCRYPTION_KEY_FILE"
fi
if [[ -z "${LLM_BIFROST_ADMIN_PASSWORD:-}" && ! -e "$ADMIN_PASSWORD_FILE" ]]; then
  openssl rand -base64 24 > "$ADMIN_PASSWORD_FILE"
fi
if [[ -z "${LLM_BIFROST_ENCRYPTION_KEY:-}" ]]; then
  LLM_BIFROST_ENCRYPTION_KEY="$(cat "$ENCRYPTION_KEY_FILE")"
fi
LLM_BIFROST_ADMIN_USERNAME=${LLM_BIFROST_ADMIN_USERNAME:-admin}
if [[ -z "${LLM_BIFROST_ADMIN_PASSWORD:-}" ]]; then
  LLM_BIFROST_ADMIN_PASSWORD="$(cat "$ADMIN_PASSWORD_FILE")"
fi

set_env_from_aliases() {
  local target="$1"
  shift
  local candidate

  if [[ -n "${!target:-}" ]]; then
    return 0
  fi

  for candidate in "$@"; do
    if [[ -n "${!candidate:-}" ]]; then
      export "$target=${!candidate}"
      return 0
    fi
  done
}

set_env_from_aliases OPENROUTER_API_KEY LLM_BIFROST_OPENROUTER_API_KEY LLM_OPENROUTER_API_KEY
set_env_from_aliases DEEPSEEK_API_KEY LLM_BIFROST_DEEPSEEK_API_KEY LLM_DEEPSEEK_API_KEY
set_env_from_aliases GLM_API_KEY LLM_BIFROST_GLM_API_KEY BIGMODEL_API_KEY LLM_BIGMODEL_API_KEY ZHIPU_API_KEY LLM_ZHIPU_API_KEY
set_env_from_aliases TENCENTCLOUD_API_KEY LLM_BIFROST_TENCENTCLOUD_API_KEY LLM_TENCENTCLOUD_API_KEY TENCENT_API_KEY
set_env_from_aliases AIHUBMIX_API_KEY LLM_BIFROST_AIHUBMIX_API_KEY LLM_AIHUBMIX_API_KEY
set_env_from_aliases VERTEX_PROJECT_ID LLM_BIFROST_VERTEX_PROJECT_ID GOOGLE_VERTEX_PROJECT_ID LLM_VERTEX_PROJECT_ID
set_env_from_aliases VERTEX_REGION LLM_BIFROST_VERTEX_REGION GOOGLE_VERTEX_REGION LLM_VERTEX_REGION
set_env_from_aliases BIFROST_PG_HOST LLM_BIFROST_POSTGRES_HOST
set_env_from_aliases BIFROST_PG_PORT LLM_BIFROST_POSTGRES_PORT
set_env_from_aliases BIFROST_PG_USER LLM_BIFROST_POSTGRES_USER
set_env_from_aliases BIFROST_PG_PASSWORD LLM_BIFROST_POSTGRES_PASSWORD
set_env_from_aliases BIFROST_PG_DB LLM_BIFROST_POSTGRES_DB
set_env_from_aliases BIFROST_PG_SSL_MODE LLM_BIFROST_POSTGRES_SSL_MODE
set_env_from_aliases S3_BUCKET LLM_BIFROST_S3_BUCKET
set_env_from_aliases S3_PREFIX LLM_BIFROST_S3_PREFIX
set_env_from_aliases S3_REGION LLM_BIFROST_S3_REGION
set_env_from_aliases S3_ENDPOINT LLM_BIFROST_S3_ENDPOINT
set_env_from_aliases S3_ACCESS_KEY_ID LLM_BIFROST_S3_ACCESS_KEY_ID
set_env_from_aliases S3_SECRET_ACCESS_KEY LLM_BIFROST_S3_SECRET_ACCESS_KEY
set_env_from_aliases BIFROST_REDIS_ADDR LLM_BIFROST_REDIS_ADDR
set_env_from_aliases BIFROST_REDIS_PASSWORD LLM_BIFROST_REDIS_PASSWORD

if [[ -n "${BIFROST_PG_HOST:-}" ]]; then
  export BIFROST_PG_PORT="${BIFROST_PG_PORT:-5432}"
  export BIFROST_PG_USER="${BIFROST_PG_USER:-bifrost}"
  export BIFROST_PG_DB="${BIFROST_PG_DB:-bifrost}"
  export BIFROST_PG_SSL_MODE="${BIFROST_PG_SSL_MODE:-disable}"
fi
if [[ -n "${S3_BUCKET:-}" ]]; then
  export S3_PREFIX="${S3_PREFIX:-bifrost}"
  export S3_REGION="${S3_REGION:-us-east-1}"
fi

LLM_BIFROST_ENV=(
  -e APP_HOST=0.0.0.0
  -e APP_PORT="$LLM_BIFROST_PORT"
  -e LOG_LEVEL="${LLM_BIFROST_LOG_LEVEL:-info}"
  -e LOG_STYLE="${LLM_BIFROST_LOG_STYLE:-json}"
  -e BIFROST_ENCRYPTION_KEY="$LLM_BIFROST_ENCRYPTION_KEY"
  -e BIFROST_ADMIN_USERNAME="$LLM_BIFROST_ADMIN_USERNAME"
  -e BIFROST_ADMIN_PASSWORD="$LLM_BIFROST_ADMIN_PASSWORD"
)

PASS_THROUGH_ENV=(
  OPENROUTER_API_KEY
  DEEPSEEK_API_KEY
  GLM_API_KEY
  TENCENTCLOUD_API_KEY
  AIHUBMIX_API_KEY
  VERTEX_PROJECT_ID
  VERTEX_REGION
  BIFROST_PG_HOST
  BIFROST_PG_PORT
  BIFROST_PG_USER
  BIFROST_PG_PASSWORD
  BIFROST_PG_DB
  BIFROST_PG_SSL_MODE
  S3_BUCKET
  S3_PREFIX
  S3_REGION
  S3_ENDPOINT
  S3_ACCESS_KEY_ID
  S3_SECRET_ACCESS_KEY
  BIFROST_REDIS_ADDR
  BIFROST_REDIS_PASSWORD
  HTTP_PROXY
  HTTPS_PROXY
  NO_PROXY
)

for ENV_NAME in "${PASS_THROUGH_ENV[@]}"; do
  if [[ -n "${!ENV_NAME:-}" ]]; then
    LLM_BIFROST_ENV+=(-e "$ENV_NAME=${!ENV_NAME}")
  fi
done

LLM_BIFROST_OPTIONS=(
  --mount type=bind,source="$LLM_BIFROST_DATA_DIR",target=/app/data
)

if [[ "$LLM_BIFROST_CONFIG_FILE" != "$LLM_BIFROST_DATA_DIR/config.json" ]]; then
  LLM_BIFROST_OPTIONS+=(
    --mount type=bind,source="$LLM_BIFROST_CONFIG_FILE",target=/app/data/config.json,ro
  )
fi

if [[ -n "${LLM_BIFROST_GOOGLE_APPLICATION_CREDENTIALS:-}" ]]; then
  LLM_BIFROST_OPTIONS+=(
    --mount type=bind,source="$LLM_BIFROST_GOOGLE_APPLICATION_CREDENTIALS",target=/app/data/google-application-credentials.json,ro
  )
  LLM_BIFROST_ENV+=(-e GOOGLE_APPLICATION_CREDENTIALS=/app/data/google-application-credentials.json)
fi

LLM_BIFROST_HAS_HOST_NETWORK=0
if [[ -n "${LLM_BIFROST_NETWORK:-}" ]]; then
  for network in ${LLM_BIFROST_NETWORK[@]}; do
    LLM_BIFROST_OPTIONS+=("--network=$network")
    if [[ "$network" == "host" ]]; then
      LLM_BIFROST_HAS_HOST_NETWORK=1
    fi
  done
fi
if [[ $LLM_BIFROST_HAS_HOST_NETWORK -eq 0 ]]; then
  LLM_BIFROST_OPTIONS+=(-p "$LLM_BIFROST_PORT:$LLM_BIFROST_PORT")
fi

echo "Bifrost image: $LLM_BIFROST_IMAGE_URL"
echo "Bifrost listen port: $LLM_BIFROST_PORT"
echo "Bifrost data dir: $LLM_BIFROST_DATA_DIR"
echo "Bifrost config file: $LLM_BIFROST_CONFIG_FILE"
echo "Bifrost admin username: $LLM_BIFROST_ADMIN_USERNAME"
echo "Bifrost admin password source: $BIFROST_ADMIN_PASSWORD_SOURCE"

if [[ -n "${LLM_BIFROST_DRY_RUN:-}" ]]; then
  echo "LLM_BIFROST_DRY_RUN is set; skipping systemd/quadlet creation."
  exit 0
fi

if "${SYSTEMCTL[@]}" --all | grep -F "$SERVICE_NAME.service" >/dev/null 2>&1; then
  "${SYSTEMCTL[@]}" stop "$SERVICE_NAME.service" || true
  "${SYSTEMCTL[@]}" disable "$SERVICE_NAME.service" || true
fi

rm -f "$SYSTEMD_CONTAINER_DIR/$SERVICE_NAME.container"
rm -f "$SYSTEMD_SERVICE_DIR/$SERVICE_NAME.service"

if podman container inspect "$SERVICE_NAME" >/dev/null 2>&1; then
  podman stop "$SERVICE_NAME" || true
  podman rm -f "$SERVICE_NAME"
fi

if [[ -n "${LLM_UPDATE:-}" || -n "${ROUTER_IMAGE_UPDATE:-}" ]]; then
  podman image prune -a -f --filter "until=240h"
fi

PODLET_RUN=()
FIND_PODLET_RESULT=1
if command -v podlet >/dev/null 2>&1; then
  PODLET_RUN=(podlet)
  FIND_PODLET_RESULT=0
else
  if podman image inspect "$PODLET_IMAGE_URL" >/dev/null 2>&1 || podman pull "$PODLET_IMAGE_URL"; then
    PODLET_RUN=(podman run --rm "$PODLET_IMAGE_URL")
    FIND_PODLET_RESULT=0
  fi
fi

if [[ $FIND_PODLET_RESULT -eq 0 ]]; then
  PODLET_OPTIONS=(--install --wanted-by default.target --wants network-online.target --after network-online.target)
  for network in ${LLM_BIFROST_NETWORK[@]}; do
    if [[ -e "$SYSTEMD_CONTAINER_DIR/$network.network" ]]; then
      PODLET_OPTIONS+=(--after "$network-network.service" --wants "$network-network.service")
    fi
  done

  "${PODLET_RUN[@]}" "${PODLET_OPTIONS[@]}" \
    podman run --name "$SERVICE_NAME" --security-opt label=disable \
      "${LLM_BIFROST_ENV[@]}" "${LLM_BIFROST_OPTIONS[@]}" \
      "$LLM_BIFROST_IMAGE_URL" | tee -p "$SYSTEMD_CONTAINER_DIR/$SERVICE_NAME.container"
else
  podman run -d --name "$SERVICE_NAME" --security-opt label=disable \
    "${LLM_BIFROST_ENV[@]}" "${LLM_BIFROST_OPTIONS[@]}" \
    "$LLM_BIFROST_IMAGE_URL"

  podman generate systemd "$SERVICE_NAME" | tee -p "$SYSTEMD_SERVICE_DIR/$SERVICE_NAME.service"
  podman container stop "$SERVICE_NAME"
fi

"${SYSTEMCTL[@]}" daemon-reload
if [[ $FIND_PODLET_RESULT -ne 0 ]]; then
  "${SYSTEMCTL[@]}" enable "$SERVICE_NAME.service"
fi
"${SYSTEMCTL[@]}" start "$SERVICE_NAME.service"

if [[ -n "${LLM_UPDATE:-}" || -n "${ROUTER_IMAGE_UPDATE:-}" ]]; then
  podman image prune -a -f --filter "until=240h"
fi

echo "Bifrost is starting. Open http://127.0.0.1:$LLM_BIFROST_PORT/ for the dashboard."
