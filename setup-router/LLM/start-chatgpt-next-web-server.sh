#!/bin/bash

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"

# Require net.ipv4.ip_unprivileged_port_start=80 in /etc/sysctl.d/*.conf
# See https://github.com/containers/podman/blob/master/rootless.md

if [[ "x$LLM_UPDATE" != "x" ]] || [[ "x$ROUTER_IMAGE_UPDATE" != "x" ]]; then
  podman pull docker.io/yidadaa/chatgpt-next-web:latest
  if [[ $? -ne 0 ]]; then
    echo "Pull docker.io/yidadaa/chatgpt-next-web:latest failed"
    exit 1
  fi
fi

if [[ -z "$LLM_CHATGPT_NEXT_WEB_PORT" ]]; then
  LLM_CHATGPT_NEXT_WEB_PORT=3005
fi

LLM_CHATGPT_NEXT_WEB_OPENAI_API_KEY=sk-
# LLM_CHATGPT_NEXT_WEB_PROXY_URL=https://owent-one-api.imwe.chat
LLM_CHATGPT_NEXT_WEB_BASE_URL=https://litellm.imwe.chat
# LLM_CHATGPT_NEXT_WEB_OPENAI_ORG_ID=
# LLM_CHATGPT_NEXT_WEB_AZURE_URL=
# LLM_CHATGPT_NEXT_WEB_AZURE_API_KEY=
# LLM_CHATGPT_NEXT_WEB_AZURE_API_VERSION=
# LLM_CHATGPT_NEXT_WEB_GOOGLE_API_KEY=
# LLM_CHATGPT_NEXT_WEB_GOOGLE_URL=https://litellm.imwe.chat
# LLM_CHATGPT_NEXT_WEB_ANTHROPIC_API_KEY=
# LLM_CHATGPT_NEXT_WEB_ANTHROPIC_API_VERSION=
# LLM_CHATGPT_NEXT_WEB_ANTHROPIC_URL=
# LLM_CHATGPT_NEXT_WEB_HIDE_USER_API_KEY=1
# LLM_CHATGPT_NEXT_WEB_DISABLE_GPT4=1
# LLM_CHATGPT_NEXT_WEB_ENABLE_BALANCE_QUERY=1
# LLM_CHATGPT_NEXT_WEB_DISABLE_FAST_LINK=1
# LLM_CHATGPT_NEXT_WEB_WHITE_WEBDEV_ENDPOINTS=1
LLM_CHATGPT_NEXT_WEB_CUSTOM_MODELS=-all,+gemini-pro,+gemini-pro-vision,+gpt-4-32k,+gpt-4-turbo,+gpt-3.5-turbo-16k,+gpt-3.5-turbo

# Password
if [[ -e "$SCRIPT_DIR/llm-chatgpt-next-web.CODE" ]]; then
  LLM_CHATGPT_NEXT_WEB_CODE="$(cat "$SCRIPT_DIR/llm-chatgpt-next-web.CODE")"
else
  LLM_CHATGPT_NEXT_WEB_CODE="sk-$(head -c 12 /dev/urandom | base64)"
  echo "$LLM_CHATGPT_NEXT_WEB_CODE" >"$SCRIPT_DIR/llm-chatgpt-next-web.CODE"
fi

if [[ "root" == "$(id -un)" ]]; then
  SYSTEMD_SERVICE_DIR=/lib/systemd/system
else
  SYSTEMD_SERVICE_DIR="$HOME/.config/systemd/user"
  mkdir -p "$SYSTEMD_SERVICE_DIR"
fi

if [[ "$SYSTEMD_SERVICE_DIR" == "/lib/systemd/system" ]]; then
  systemctl --all | grep -F llm-chatgpt-next-web.service >/dev/null 2>&1
  if [ $? -eq 0 ]; then
    systemctl stop llm-chatgpt-next-web.service
    systemctl disable llm-chatgpt-next-web.service
  fi
else
  export XDG_RUNTIME_DIR="/run/user/$UID"
  export DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR}/bus"

  # Maybe need run from host: loginctl enable-linger tools
  # see https://wiki.archlinux.org/index.php/Systemd/User
  # sudo loginctl enable-linger $RUN_USER
  systemctl --user --all | grep -F llm-chatgpt-next-web.service >/dev/null 2>&1
  if [ $? -eq 0 ]; then
    systemctl --user stop llm-chatgpt-next-web.service
    systemctl --user disable llm-chatgpt-next-web.service
  fi
fi

podman container inspect llm-chatgpt-next-web >/dev/null 2>&1

if [[ $? -eq 0 ]]; then
  podman stop llm-chatgpt-next-web
  podman rm -f llm-chatgpt-next-web
fi

if [[ "x$LLM_UPDATE" != "x" ]] || [[ "x$ROUTER_IMAGE_UPDATE" != "x" ]]; then
  podman image prune -a -f --filter "until=240h"
fi

LLM_CHATGPT_NEXT_WEB_ENV=(
  -e TZ=Asia/Shanghai
  -e CODE=$LLM_CHATGPT_NEXT_WEB_CODE
  -e OPENAI_API_KEY=$LLM_CHATGPT_NEXT_WEB_OPENAI_API_KEY
)
if [[ ! -z "$LLM_CHATGPT_NEXT_WEB_PROXY_URL" ]]; then
  LLM_CHATGPT_NEXT_WEB_ENV=(${LLM_CHATGPT_NEXT_WEB_ENV[@]} -e PROXY_URL="$LLM_CHATGPT_NEXT_WEB_PROXY_URL")
fi
if [[ ! -z "$LLM_CHATGPT_NEXT_WEB_BASE_URL" ]]; then
  LLM_CHATGPT_NEXT_WEB_ENV=(${LLM_CHATGPT_NEXT_WEB_ENV[@]} -e BASE_URL="$LLM_CHATGPT_NEXT_WEB_BASE_URL")
fi
if [[ ! -z "$LLM_CHATGPT_NEXT_WEB_OPENAI_ORG_ID" ]]; then
  LLM_CHATGPT_NEXT_WEB_ENV=(${LLM_CHATGPT_NEXT_WEB_ENV[@]} -e OPENAI_ORG_ID="$LLM_CHATGPT_NEXT_WEB_OPENAI_ORG_ID")
fi
if [[ ! -z "$LLM_CHATGPT_NEXT_WEB_PROXY_URL" ]]; then
  LLM_CHATGPT_NEXT_WEB_ENV=(${LLM_CHATGPT_NEXT_WEB_ENV[@]} -e PROXY_URL="$LLM_CHATGPT_NEXT_WEB_PROXY_URL")
fi
if [[ ! -z "$LLM_CHATGPT_NEXT_WEB_PROXY_URL" ]]; then
  LLM_CHATGPT_NEXT_WEB_ENV=(${LLM_CHATGPT_NEXT_WEB_ENV[@]} -e PROXY_URL="$LLM_CHATGPT_NEXT_WEB_PROXY_URL")
fi
if [[ ! -z "LLM_CHATGPT_NEXT_WEB_AZURE_URL" ]]; then
  LLM_CHATGPT_NEXT_WEB_ENV=(${LLM_CHATGPT_NEXT_WEB_ENV[@]} -e AZURE_URL="$LLM_CHATGPT_NEXT_WEB_AZURE_URL")
fi
if [[ ! -z "LLM_CHATGPT_NEXT_WEB_AZURE_API_KEY" ]]; then
  LLM_CHATGPT_NEXT_WEB_ENV=(${LLM_CHATGPT_NEXT_WEB_ENV[@]} -e AZURE_API_KEY="$LLM_CHATGPT_NEXT_WEB_AZURE_API_KEY")
fi
if [[ ! -z "LLM_CHATGPT_NEXT_WEB_AZURE_API_VERSION" ]]; then
  LLM_CHATGPT_NEXT_WEB_ENV=(${LLM_CHATGPT_NEXT_WEB_ENV[@]} -e AZURE_API_VERSION="$LLM_CHATGPT_NEXT_WEB_AZURE_API_VERSION")
fi
if [[ ! -z "LLM_CHATGPT_NEXT_WEB_GOOGLE_API_KEY" ]]; then
  LLM_CHATGPT_NEXT_WEB_ENV=(${LLM_CHATGPT_NEXT_WEB_ENV[@]} -e GOOGLE_API_KEY="$LLM_CHATGPT_NEXT_WEB_GOOGLE_API_KEY")
fi
if [[ ! -z "LLM_CHATGPT_NEXT_WEB_GOOGLE_URL" ]]; then
  LLM_CHATGPT_NEXT_WEB_ENV=(${LLM_CHATGPT_NEXT_WEB_ENV[@]} -e GOOGLE_URL="$LLM_CHATGPT_NEXT_WEB_GOOGLE_URL")
fi
if [[ ! -z "LLM_CHATGPT_NEXT_WEB_ANTHROPIC_API_KEY" ]]; then
  LLM_CHATGPT_NEXT_WEB_ENV=(${LLM_CHATGPT_NEXT_WEB_ENV[@]} -e ANTHROPIC_API_KEY="$LLM_CHATGPT_NEXT_WEB_ANTHROPIC_API_KEY")
fi
if [[ ! -z "LLM_CHATGPT_NEXT_WEB_ANTHROPIC_API_VERSION" ]]; then
  LLM_CHATGPT_NEXT_WEB_ENV=(${LLM_CHATGPT_NEXT_WEB_ENV[@]} -e ANTHROPIC_API_VERSION="$LLM_CHATGPT_NEXT_WEB_ANTHROPIC_API_VERSION")
fi
if [[ ! -z "LLM_CHATGPT_NEXT_WEB_ANTHROPIC_URL" ]]; then
  LLM_CHATGPT_NEXT_WEB_ENV=(${LLM_CHATGPT_NEXT_WEB_ENV[@]} -e ANTHROPIC_URL="$LLM_CHATGPT_NEXT_WEB_ANTHROPIC_URL")
fi
if [[ ! -z "LLM_CHATGPT_NEXT_WEB_HIDE_USER_API_KEY" ]]; then
  LLM_CHATGPT_NEXT_WEB_ENV=(${LLM_CHATGPT_NEXT_WEB_ENV[@]} -e HIDE_USER_API_KEY="$LLM_CHATGPT_NEXT_WEB_HIDE_USER_API_KEY")
fi
if [[ ! -z "LLM_CHATGPT_NEXT_WEB_DISABLE_GPT4" ]]; then
  LLM_CHATGPT_NEXT_WEB_ENV=(${LLM_CHATGPT_NEXT_WEB_ENV[@]} -e DISABLE_GPT4="$LLM_CHATGPT_NEXT_WEB_DISABLE_GPT4")
fi
if [[ ! -z "LLM_CHATGPT_NEXT_WEB_ENABLE_BALANCE_QUERY" ]]; then
  LLM_CHATGPT_NEXT_WEB_ENV=(${LLM_CHATGPT_NEXT_WEB_ENV[@]} -e ENABLE_BALANCE_QUERY="$LLM_CHATGPT_NEXT_WEB_ENABLE_BALANCE_QUERY")
fi
if [[ ! -z "LLM_CHATGPT_NEXT_WEB_DISABLE_FAST_LINK" ]]; then
  LLM_CHATGPT_NEXT_WEB_ENV=(${LLM_CHATGPT_NEXT_WEB_ENV[@]} -e DISABLE_FAST_LINK="$LLM_CHATGPT_NEXT_WEB_DISABLE_FAST_LINK")
fi
if [[ ! -z "LLM_CHATGPT_NEXT_WEB_WHITE_WEBDEV_ENDPOINTS" ]]; then
  LLM_CHATGPT_NEXT_WEB_ENV=(${LLM_CHATGPT_NEXT_WEB_ENV[@]} -e WHITE_WEBDEV_ENDPOINTS="$LLM_CHATGPT_NEXT_WEB_WHITE_WEBDEV_ENDPOINTS")
fi
if [[ ! -z "LLM_CHATGPT_NEXT_WEB_WHITE_WEBDEV_ENDPOINTS" ]]; then
  LLM_CHATGPT_NEXT_WEB_ENV=(${LLM_CHATGPT_NEXT_WEB_ENV[@]} -e CUSTOM_MODELS="$LLM_CHATGPT_NEXT_WEB_CUSTOM_MODELS")
fi

podman run -d --name llm-chatgpt-next-web --security-opt label=disable \
  ${LLM_CHATGPT_NEXT_WEB_ENV[@]} \
  -p $LLM_CHATGPT_NEXT_WEB_PORT:3000 \
  docker.io/yidadaa/chatgpt-next-web:latest

podman generate systemd llm-chatgpt-next-web | tee -p "$SYSTEMD_SERVICE_DIR/llm-chatgpt-next-web.service"
podman container stop llm-chatgpt-next-web

if [[ "$SYSTEMD_SERVICE_DIR" == "/lib/systemd/system" ]]; then
  systemctl enable llm-chatgpt-next-web.service
  systemctl daemon-reload
  systemctl start llm-chatgpt-next-web.service
else
  systemctl --user enable "$SYSTEMD_SERVICE_DIR/llm-chatgpt-next-web.service"
  systemctl --user daemon-reload
  systemctl --user start llm-chatgpt-next-web.service
fi
