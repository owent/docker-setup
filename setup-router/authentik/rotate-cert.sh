#!/bin/bash

# 更新证书

if [[ $# -lt 3 ]]; then
    echo "Usage: $0 <cert name> <fullchain-file> <priv-key-file>"
    exit 1
fi

CERT_NAME="$1"
FULLCHAIN_FILE="$2"
PRIVKEY_FILE="$3"

if [[ ! -e "$FULLCHAIN_FILE" ]]; then
  echo "Fullchain file $FULLCHAIN_FILE does not exist"
  exit 1
fi

if [[ ! -e "$PRIVKEY_FILE" ]]; then
  echo "Private key file $PRIVKEY_FILE does not exist"
  exit 1
fi

if [[ ! -z "$AUTHENTIK_TOKEN" ]] && [[ ! -z "$AUTHENTIK_URL" ]]; then
  CRT=$(jq -Rs . < "$FULLCHAIN_FILE")
  KEY=$(jq -Rs . < "$PRIVKEY_FILE")

  CK_ID=$(curl -s \
    -H "Authorization: Bearer ${AUTHENTIK_TOKEN}" \
    "${AUTHENTIK_URL}/api/v3/crypto/certificatekeypairs/" |
    jq -r --arg NAME "$CERT_NAME" '.results[] | select(.name==$NAME) | .pk')
  if [[ -z "$CK_ID" ]]; then
    echo "Can not find key id for $CERT_NAME"
    exit 1
  fi

  echo "Update cert $CERT_NAME -> $FULLCHAIN_FILE/$PRIVKEY_FILE"
  curl -X PATCH \
    -H "Authorization: Bearer ${AUTHENTIK_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "{\"certificate\": ${CRT}, \"key\": ${KEY}}" \
    "${AUTHENTIK_URL}/api/v3/crypto/certificatekeypairs/${CK_ID}/"
else
  export XDG_RUNTIME_DIR="/run/user/$UID"
  export DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR}/bus"

  DOCKER_EXEC=$((which podman > /dev/null 2>&1 && echo podman) || (which docker > /dev/null 2>&1 && echo docker))

  echo "Update cert $CERT_NAME -> $FULLCHAIN_FILE/$PRIVKEY_FILE"

  $DOCKER_EXEC exec authentik-server bash -c "mkdir -p '/certs/$CERT_NAME'"
  $DOCKER_EXEC cp "$FULLCHAIN_FILE" "authentik-server:/certs/$CERT_NAME/fullchain.pem"
  $DOCKER_EXEC cp "$PRIVKEY_FILE" "authentik-server:/certs/$CERT_NAME/privkey.pem"
  $DOCKER_EXEC exec authentik-server ak import_certificate \
    --certificate "/certs/$CERT_NAME/fullchain.pem" \
    --private-key "/certs/$CERT_NAME/privkey.pem" \
    --name "$CERT_NAME"
fi
