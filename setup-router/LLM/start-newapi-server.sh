#!/bin/bash
set -e

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
SERVICE_NAME="llm-newapi"
PODLET_IMAGE_URL=${PODLET_IMAGE_URL:-"ghcr.io/containers/podlet:latest"}

if [[ "root" == "$(id -un)" ]]; then
  SYSTEMD_SERVICE_DIR=/lib/systemd/system
  SYSTEMD_CONTAINER_DIR=/etc/containers/systemd
  SYSTEMCTL=(systemctl)
  DEFAULT_NEWAPI_DATA_DIR=/var/lib/llm/new-api/data
  DEFAULT_NEWAPI_LOG_DIR=/var/log/llm/new-api
else
  SYSTEMD_SERVICE_DIR="$HOME/.config/systemd/user"
  SYSTEMD_CONTAINER_DIR="$HOME/.config/containers/systemd"
  SYSTEMCTL=(systemctl --user)
  DEFAULT_NEWAPI_DATA_DIR="$HOME/llm/new-api/data"
  DEFAULT_NEWAPI_LOG_DIR="$HOME/llm/new-api/logs"
  export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$UID}"
  export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=${XDG_RUNTIME_DIR}/bus}"
fi

mkdir -p "$SYSTEMD_SERVICE_DIR"
mkdir -p "$SYSTEMD_CONTAINER_DIR"

LLM_NEWAPI_IMAGE_URL=${LLM_NEWAPI_IMAGE_URL:-"docker.io/calciumion/new-api:latest"}
LLM_NEWAPI_PORT=${LLM_NEWAPI_PORT:-3000}
LLM_NEWAPI_DATA_DIR=${LLM_NEWAPI_DATA_DIR:-"$DEFAULT_NEWAPI_DATA_DIR"}
LLM_NEWAPI_LOG_DIR=${LLM_NEWAPI_LOG_DIR:-"$DEFAULT_NEWAPI_LOG_DIR"}
LLM_NEWAPI_REDIS_DB=${LLM_NEWAPI_REDIS_DB:-14}
LLM_NEWAPI_SQLITE_PATH=${LLM_NEWAPI_SQLITE_PATH:-"/data/new-api.db"}

mkdir -p "$LLM_NEWAPI_DATA_DIR"
mkdir -p "$LLM_NEWAPI_LOG_DIR"

if [[ -n "${LLM_UPDATE:-}" || -n "${ROUTER_IMAGE_UPDATE:-}" ]]; then
  podman pull "$LLM_NEWAPI_IMAGE_URL"
fi

SECRET_DIR="$LLM_NEWAPI_DATA_DIR/secrets"
SESSION_SECRET_FILE="$SECRET_DIR/SESSION_SECRET"
CRYPTO_SECRET_FILE="$SECRET_DIR/CRYPTO_SECRET"
mkdir -p "$SECRET_DIR"

if [[ -z "${LLM_NEWAPI_SESSION_SECRET:-}" && ! -e "$SESSION_SECRET_FILE" ]]; then
  openssl rand -hex 32 > "$SESSION_SECRET_FILE"
fi
if [[ -z "${LLM_NEWAPI_CRYPTO_SECRET:-}" && ! -e "$CRYPTO_SECRET_FILE" ]]; then
  openssl rand -hex 32 > "$CRYPTO_SECRET_FILE"
fi
if [[ -z "${LLM_NEWAPI_SESSION_SECRET:-}" ]]; then
  LLM_NEWAPI_SESSION_SECRET="$(cat "$SESSION_SECRET_FILE")"
fi
if [[ -z "${LLM_NEWAPI_CRYPTO_SECRET:-}" ]]; then
  LLM_NEWAPI_CRYPTO_SECRET="$(cat "$CRYPTO_SECRET_FILE")"
fi

build_redis_url() {
  local auth=""
  local host="${LLM_NEWAPI_REDIS_HOST:-}"
  local port="${LLM_NEWAPI_REDIS_PORT:-6379}"
  local db="${LLM_NEWAPI_REDIS_DB:-14}"

  if [[ -z "$host" ]]; then
    return 0
  fi

  if [[ -n "${LLM_NEWAPI_REDIS_USERNAME:-}" || -n "${LLM_NEWAPI_REDIS_PASSWORD:-}" ]]; then
    auth="${LLM_NEWAPI_REDIS_USERNAME:-}"
    if [[ -n "${LLM_NEWAPI_REDIS_PASSWORD:-}" ]]; then
      auth="${auth}:${LLM_NEWAPI_REDIS_PASSWORD}"
    fi
    auth="${auth}@"
  fi

  echo "redis://${auth}${host}:${port}/${db}"
}

build_postgres_dsn() {
  local host="${LLM_NEWAPI_POSTGRES_HOST:-}"
  local port="${LLM_NEWAPI_POSTGRES_PORT:-5432}"
  local user="${LLM_NEWAPI_POSTGRES_USER:-newapi}"
  local password="${LLM_NEWAPI_POSTGRES_PASSWORD:-}"
  local db="${LLM_NEWAPI_POSTGRES_DB:-newapi}"
  local sslmode="${LLM_NEWAPI_POSTGRES_SSLMODE:-disable}"

  if [[ -z "$host" ]]; then
    return 0
  fi

  if [[ -n "$password" ]]; then
    echo "postgresql://${user}:${password}@${host}:${port}/${db}?sslmode=${sslmode}"
  else
    echo "postgresql://${user}@${host}:${port}/${db}?sslmode=${sslmode}"
  fi
}

LLM_NEWAPI_ENV=(
  -e TZ="${TZ:-Asia/Shanghai}"
  -e SESSION_SECRET="$LLM_NEWAPI_SESSION_SECRET"
  -e CRYPTO_SECRET="$LLM_NEWAPI_CRYPTO_SECRET"
  -e SQLITE_PATH="$LLM_NEWAPI_SQLITE_PATH"
  -e SQL_MAX_IDLE_CONNS="${LLM_NEWAPI_SQL_MAX_IDLE_CONNS:-10}"
  -e SQL_MAX_OPEN_CONNS="${LLM_NEWAPI_SQL_MAX_OPEN_CONNS:-50}"
  -e RELAY_MAX_IDLE_CONNS="${LLM_NEWAPI_RELAY_MAX_IDLE_CONNS:-100}"
  -e RELAY_MAX_IDLE_CONNS_PER_HOST="${LLM_NEWAPI_RELAY_MAX_IDLE_CONNS_PER_HOST:-50}"
  -e MAX_REQUEST_BODY_MB="${LLM_NEWAPI_MAX_REQUEST_BODY_MB:-64}"
  -e STREAM_SCANNER_MAX_BUFFER_MB="${LLM_NEWAPI_STREAM_SCANNER_MAX_BUFFER_MB:-16}"
  -e MEMORY_CACHE_ENABLED="${LLM_NEWAPI_MEMORY_CACHE_ENABLED:-false}"
  -e ERROR_LOG_ENABLED="${LLM_NEWAPI_ERROR_LOG_ENABLED:-true}"
  -e BATCH_UPDATE_ENABLED="${LLM_NEWAPI_BATCH_UPDATE_ENABLED:-true}"
  -e CHANNEL_UPSTREAM_MODEL_UPDATE_TASK_ENABLED="${LLM_NEWAPI_CHANNEL_UPSTREAM_MODEL_UPDATE_TASK_ENABLED:-true}"
  -e SYNC_FREQUENCY="${LLM_NEWAPI_SYNC_FREQUENCY:-10}"
)

NEWAPI_SQL_DSN="${SQL_DSN:-${LLM_NEWAPI_SQL_DSN:-$(build_postgres_dsn)}}"
if [[ -n "$NEWAPI_SQL_DSN" ]]; then
  LLM_NEWAPI_ENV+=(-e SQL_DSN="$NEWAPI_SQL_DSN")
fi

NEWAPI_REDIS_CONN_STRING="${REDIS_CONN_STRING:-${LLM_NEWAPI_REDIS_CONN_STRING:-$(build_redis_url)}}"
if [[ -n "$NEWAPI_REDIS_CONN_STRING" ]]; then
  LLM_NEWAPI_ENV+=(
    -e REDIS_CONN_STRING="$NEWAPI_REDIS_CONN_STRING"
    -e REDIS_POOL_SIZE="${LLM_NEWAPI_REDIS_POOL_SIZE:-10}"
  )
fi

PASS_THROUGH_ENV=(
  FRONTEND_BASE_URL
  LOG_SQL_DSN
  NODE_TYPE
  RELAY_TIMEOUT
  STREAMING_TIMEOUT
  CountToken
  GET_MEDIA_TOKEN
  GET_MEDIA_TOKEN_NOT_STREAM
  UPDATE_TASK
  TASK_QUERY_LIMIT
  TASK_TIMEOUT_MINUTES
  SYNC_UPSTREAM_BASE
  TLS_INSECURE_SKIP_VERIFY
  GENERATE_DEFAULT_TOKEN
  DEBUG
  GIN_MODE
  ENABLE_PPROF
  HTTP_PROXY
  HTTPS_PROXY
  NO_PROXY
)

for ENV_NAME in "${PASS_THROUGH_ENV[@]}"; do
  PREFIXED_ENV_NAME="LLM_NEWAPI_${ENV_NAME}"
  if [[ -n "${!PREFIXED_ENV_NAME:-}" ]]; then
    LLM_NEWAPI_ENV+=(-e "$ENV_NAME=${!PREFIXED_ENV_NAME}")
  elif [[ -n "${!ENV_NAME:-}" ]]; then
    LLM_NEWAPI_ENV+=(-e "$ENV_NAME=${!ENV_NAME}")
  fi
done

LLM_NEWAPI_OPTIONS=(
  --mount type=bind,source="$LLM_NEWAPI_DATA_DIR",target=/data
  --mount type=bind,source="$LLM_NEWAPI_LOG_DIR",target=/app/logs
)

LLM_NEWAPI_HAS_HOST_NETWORK=0
if [[ -n "${LLM_NEWAPI_NETWORK:-}" ]]; then
  for network in ${LLM_NEWAPI_NETWORK[@]}; do
    LLM_NEWAPI_OPTIONS+=("--network=$network")
    if [[ "$network" == "host" ]]; then
      LLM_NEWAPI_HAS_HOST_NETWORK=1
    fi
  done
fi
if [[ $LLM_NEWAPI_HAS_HOST_NETWORK -eq 0 ]]; then
  LLM_NEWAPI_OPTIONS+=(-p "$LLM_NEWAPI_PORT:$LLM_NEWAPI_PORT")
fi

echo "New API image: $LLM_NEWAPI_IMAGE_URL"
echo "New API listen port: $LLM_NEWAPI_PORT"
echo "New API data dir: $LLM_NEWAPI_DATA_DIR"
echo "New API logs dir: $LLM_NEWAPI_LOG_DIR"
if [[ -n "$NEWAPI_SQL_DSN" ]]; then
  echo "New API database: SQL_DSN is configured"
else
  echo "New API database: SQLite at $LLM_NEWAPI_SQLITE_PATH"
fi
if [[ -n "$NEWAPI_REDIS_CONN_STRING" ]]; then
  echo "New API Redis: configured; use a dedicated DB index for isolation"
else
  echo "New API Redis: disabled"
fi

if [[ -n "${LLM_NEWAPI_DRY_RUN:-}" ]]; then
  echo "LLM_NEWAPI_DRY_RUN is set; skipping systemd/quadlet creation."
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
  for network in ${LLM_NEWAPI_NETWORK[@]}; do
    if [[ -e "$SYSTEMD_CONTAINER_DIR/$network.network" ]]; then
      PODLET_OPTIONS+=(--after "$network-network.service" --wants "$network-network.service")
    fi
  done

  "${PODLET_RUN[@]}" "${PODLET_OPTIONS[@]}" \
    podman run --name "$SERVICE_NAME" --security-opt label=disable \
      "${LLM_NEWAPI_ENV[@]}" "${LLM_NEWAPI_OPTIONS[@]}" \
      "$LLM_NEWAPI_IMAGE_URL" \
      --port "$LLM_NEWAPI_PORT" \
      --log-dir /app/logs | tee -p "$SYSTEMD_CONTAINER_DIR/$SERVICE_NAME.container"
else
  podman run -d --name "$SERVICE_NAME" --security-opt label=disable \
    "${LLM_NEWAPI_ENV[@]}" "${LLM_NEWAPI_OPTIONS[@]}" \
    "$LLM_NEWAPI_IMAGE_URL" \
    --port "$LLM_NEWAPI_PORT" \
    --log-dir /app/logs

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

echo "New API is starting. Open http://127.0.0.1:$LLM_NEWAPI_PORT/ to finish first-time setup."
