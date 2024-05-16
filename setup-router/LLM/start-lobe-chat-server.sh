#!/bin/bash

# https://github.com/lobehub/lobe-chat

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"

# Providers: https://lobehub.com/zh/docs/self-hosting/environment-variables/model-provider

# LLM_LOBE_CHAT_OPENAI_API_KEY=sk-
# LLM_LOBE_CHAT_OPENAI_PROXY_URL= # https://api.openai.com/v1
# LLM_LOBE_CHAT_API_KEY_SELECT_MODE=random # random,turn

# LLM_LOBE_CHAT_AZURE_API_KEY=
# LLM_LOBE_CHAT_AZURE_ENDPOINT= # https://owent-us.openai.azure.com/
# LLM_LOBE_CHAT_AZURE_MODEL_LIST=random # random,turn

# LLM_LOBE_CHAT_GOOGLE_API_KEY=
# LLM_LOBE_CHAT_GOOGLE_PROXY_URL= # https://generativelanguage.googleapis.com

# LLM_LOBE_CHAT_OLLAMA_PROXY_URL= # http://127.0.0.1:11434
# LLM_LOBE_CHAT_OLLAMA_MODEL_LIST=random # random,turn

# LLM_LOBE_CHAT_ACCESS_CODE=
# LLM_LOBE_CHAT_PORT=3210
# LLM_LOBE_CHAT_OPENAI_MODEL_LIST=-gpt-4,-gpt-4-32k,-gpt-3.5-turbo-16k,gpt-3.5-turbo-1106=gpt-3.5-turbo-16k,gpt-4-0125-preview=gpt-4-turbo,gpt-4-vision-preview=gpt-4-vision
# https://github.com/lobehub/lobe-chat/discussions/913
# LLM_LOBE_CHAT_DEFAULT_AGENT_CONFIG=model=gpt-4

# Auth: https://lobehub.com/zh/docs/self-hosting/environment-variables/auth

# LLM_LOBE_CHAT_NEXTAUTH_SECRET=$(openssl rand -base64 32)
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
