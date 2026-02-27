#!/bin/bash

# Update OpenClaw's LiteLLM provider model list by querying LiteLLM's API
# Requires: jq, curl, podman (with openclaw container running)
#
# Usage:
#   OPENCLAW_LITELLM_BASE_URL=http://litellm-host:4000 bash update-litellm-models.sh
#   OPENCLAW_LITELLM_BASE_URL=http://litellm-host:4000 OPENCLAW_LITELLM_API_KEY=sk-... bash update-litellm-models.sh
#
# See https://docs.openclaw.ai/providers/litellm

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"

if [[ -z "$OPENCLAW_LITELLM_BASE_URL" ]]; then
  echo "Error: OPENCLAW_LITELLM_BASE_URL is not set."
  echo "Usage: OPENCLAW_LITELLM_BASE_URL=http://litellm-host:4000 bash $0"
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "Error: jq is required but not installed."
  echo "Install: apt install jq  /  yum install jq  /  pacman -S jq"
  exit 1
fi

LITELLM_AUTH_HEADER=""
if [[ -n "$OPENCLAW_LITELLM_API_KEY" ]]; then
  LITELLM_AUTH_HEADER="Authorization: Bearer ${OPENCLAW_LITELLM_API_KEY}"
fi

LITELLM_CURL_OPTS=(curl -sf --connect-timeout 10 --max-time 30)
if [[ -n "$LITELLM_AUTH_HEADER" ]]; then
  LITELLM_CURL_OPTS+=(-H "$LITELLM_AUTH_HEADER")
fi

LITELLM_MODELS_JSON=""

# Try /model/info first (richer metadata: max_tokens, max_input_tokens, supports_vision, supports_reasoning)
# See https://docs.litellm.ai/docs/proxy/model_management#get-model-info
echo "Querying $OPENCLAW_LITELLM_BASE_URL/model/info ..."
LITELLM_MODEL_INFO="$("${LITELLM_CURL_OPTS[@]}" "${OPENCLAW_LITELLM_BASE_URL}/model/info" 2>/dev/null)"
if [[ $? -eq 0 ]] && [[ -n "$LITELLM_MODEL_INFO" ]]; then
  LITELLM_MODELS_JSON="$(echo "$LITELLM_MODEL_INFO" | jq -c '[
    .data[]? |
    {
      id: .model_name,
      name: ((.model_info.litellm_provider // "" | split("/") | last // .model_name) + " (" + .model_name + ")"),
      reasoning: (if .model_info.supports_reasoning == true then true else false end),
      input: (
        if .model_info.supports_vision == true then ["text", "image"]
        else ["text"]
        end
      ),
      contextWindow: (.model_info.max_input_tokens // .model_info.max_tokens // 128000),
      maxTokens: (.model_info.max_output_tokens // .model_info.max_tokens // 8192)
    }
  ] // []' 2>/dev/null)"

  if [[ $? -ne 0 ]] || [[ -z "$LITELLM_MODELS_JSON" ]]; then
    LITELLM_MODELS_JSON=""
    echo "  Failed to parse /model/info response."
  else
    MODEL_COUNT="$(echo "$LITELLM_MODELS_JSON" | jq 'length')"
    echo "  Discovered $MODEL_COUNT models from /model/info"
  fi
fi

# Fallback to /v1/models (minimal info, only model ids)
if [[ -z "$LITELLM_MODELS_JSON" ]]; then
  echo "Querying $OPENCLAW_LITELLM_BASE_URL/v1/models ..."
  LITELLM_MODELS_LIST="$("${LITELLM_CURL_OPTS[@]}" "${OPENCLAW_LITELLM_BASE_URL}/v1/models" 2>/dev/null)"
  if [[ $? -eq 0 ]] && [[ -n "$LITELLM_MODELS_LIST" ]]; then
    LITELLM_MODELS_JSON="$(echo "$LITELLM_MODELS_LIST" | jq -c '[
      .data[]? |
      {
        id: .id,
        name: .id,
        reasoning: false,
        input: ["text"],
        contextWindow: 128000,
        maxTokens: 8192
      }
    ] // []' 2>/dev/null)"

    if [[ $? -ne 0 ]] || [[ -z "$LITELLM_MODELS_JSON" ]]; then
      echo "Error: Failed to parse /v1/models response."
      exit 1
    fi
    MODEL_COUNT="$(echo "$LITELLM_MODELS_JSON" | jq 'length')"
    echo "  Discovered $MODEL_COUNT models from /v1/models (basic info only)"
  else
    echo "Error: Could not reach LiteLLM at $OPENCLAW_LITELLM_BASE_URL"
    echo "  Ensure LiteLLM is running and reachable."
    exit 1
  fi
fi

if [[ "$LITELLM_MODELS_JSON" == "[]" ]]; then
  echo "Warning: No models found from LiteLLM."
  echo "  Check your LiteLLM config and ensure models are configured."
  exit 1
fi

# Display discovered models
echo ""
echo "Models to register:"
echo "$LITELLM_MODELS_JSON" | jq -r '.[] | "  - \(.id) (\(.contextWindow) ctx, \(.maxTokens) max out, input: \(.input | join(", ")), reasoning: \(.reasoning))"'
echo ""

# Update OpenClaw config via CLI
# Ensure the litellm provider entry exists with baseUrl
echo "Updating OpenClaw LiteLLM provider config..."

export XDG_RUNTIME_DIR="/run/user/$UID"
export DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR}/bus"

# Set baseUrl (idempotent)
podman exec openclaw node openclaw.mjs config set 'models.providers.litellm.baseUrl' "$OPENCLAW_LITELLM_BASE_URL" 2>/dev/null
podman exec openclaw node openclaw.mjs config set 'models.providers.litellm.api' 'openai-completions' 2>/dev/null

# Set models list
podman exec openclaw node openclaw.mjs config set 'models.providers.litellm.models' "$LITELLM_MODELS_JSON"

if [[ $? -eq 0 ]]; then
  echo ""
  echo "Done! LiteLLM models updated in OpenClaw."
  echo ""
  echo "Set default model (example):"
  FIRST_MODEL="$(echo "$LITELLM_MODELS_JSON" | jq -r '.[0].id // empty')"
  if [[ -n "$FIRST_MODEL" ]]; then
    echo "  podman exec -it openclaw node openclaw.mjs models set \"litellm/${FIRST_MODEL}\""
  fi
  echo ""
  echo "List all LiteLLM models:"
  echo "  podman exec -it openclaw node openclaw.mjs models list --provider litellm"
else
  echo "Error: Failed to update OpenClaw config."
  echo "  Ensure the openclaw container is running."
  exit 1
fi
