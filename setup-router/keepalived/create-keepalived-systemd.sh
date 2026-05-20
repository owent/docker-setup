#!/bin/bash

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"

RUN_USER=$(id -un)
RUN_HOME=$(cat /etc/passwd | awk "BEGIN{FS=\":\"} \$1 == \"$RUN_USER\" { print \$6 }")

if [[ "$RUN_USER" != "root" ]]; then
    echo "Error: root is required, current user is $RUN_USER"
    exit 1
fi

if [[ "x$RUN_HOME" == "x" ]]; then
    RUN_HOME="$HOME"
fi

if [[ -z "$KEEPALIVED_ETC_DIR" ]]; then
    KEEPALIVED_ETC_DIR="$SCRIPT_DIR/etc"
fi
mkdir -p "$KEEPALIVED_ETC_DIR"

if [[ ! -e "$KEEPALIVED_ETC_DIR/keepalived.conf" ]]; then
    echo "Error: $KEEPALIVED_ETC_DIR/keepalived.conf is required"
    exit 1
fi

DOCKER_EXEC=podman
which podman >/dev/null 2>&1 || DOCKER_EXEC=docker

if [[ "x$KEA_UPDATE" != "x" ]] || [[ "x$ROUTER_IMAGE_UPDATE" != "x" ]]; then
    $DOCKER_EXEC pull alpine:latest
    if [[ $? -ne 0 ]]; then
        exit 1
    fi

    $DOCKER_EXEC build --network=host --tag local-keepalived -f keepalived.Dockerfile .
    if [[ $? -ne 0 ]]; then
        exit 1
    fi
else
    $DOCKER_EXEC image inspect local-keepalived >/dev/null 2>&1
    if [[ $? -ne 0 ]]; then
        $DOCKER_EXEC build --network=host --tag local-keepalived -f keepalived.Dockerfile .
        if [[ $? -ne 0 ]]; then
            exit 1
        fi
    fi
fi

if [[ "root" == "$(id -un)" ]]; then
  if [[ -e "/lib/systemd/system" ]]; then
    SYSTEMD_SERVICE_DIR=/lib/systemd/system
  elif [[ -e "/usr/lib/systemd/system" ]]; then
    SYSTEMD_SERVICE_DIR=/usr/lib/systemd/system
  else
    SYSTEMD_SERVICE_DIR=/etc/systemd/system
  fi
  SYSTEMD_CONTAINER_DIR=/etc/containers/systemd
  mkdir -p "$SYSTEMD_CONTAINER_DIR"
else
  SYSTEMD_SERVICE_DIR="$HOME/.config/systemd/user"
  SYSTEMD_CONTAINER_DIR="$HOME/.config/containers/systemd"
  mkdir -p "$SYSTEMD_SERVICE_DIR"
  mkdir -p "$SYSTEMD_CONTAINER_DIR"
fi

systemctl --all | grep -F keepalived

if [[ $? -eq 0 ]]; then
    systemctl stop keepalived
    systemctl disable keepalived
fi

$DOCKER_EXEC container inspect keepalived >/dev/null 2>&1

if [[ $? -eq 0 ]]; then
    $DOCKER_EXEC stop keepalived
    $DOCKER_EXEC rm -f keepalived
fi

if [[ "x$REDIS_UPDATE" != "x" ]] || [[ "x$ROUTER_IMAGE_UPDATE" != "x" ]]; then
    $DOCKER_EXEC image prune -a -f --filter "until=240h"
fi

KEEPALIVED_OPTIONS=(-e "TZ=Asia/Shanghai"
    --network=host
    --cap-add=NET_ADMIN
    --cap-add=NET_RAW
    --mount "type=bind,source=$KEEPALIVED_ETC_DIR,target=/etc/keepalived"
)

if [[ -e "/etc/msmtprc" ]]; then
  KEEPALIVED_OPTIONS+=("--mount" "type=bind,source=/etc/msmtprc,target=/etc/msmtprc,ro=true")
fi

PODLET_IMAGE_URL="ghcr.io/containers/podlet:latest"
PODLET_RUN=($(which podlet 2>/dev/null))
FIND_PODLET_RESULT=$?
if [[ $FIND_PODLET_RESULT -ne 0 ]]; then
  (podman image inspect "$PODLET_IMAGE_URL" > /dev/null 2>&1 || podman pull "$PODLET_IMAGE_URL") && FIND_PODLET_RESULT=0 && PODLET_RUN=(podman run --rm "$PODLET_IMAGE_URL")
fi

if [[ $FIND_PODLET_RESULT -eq 0 ]]; then
  PODLET_OPTIONS=(--install --wanted-by default.target --wants network-online.target --after network-online.target)

  ${PODLET_RUN[@]} "${PODLET_OPTIONS[@]}" \
    $DOCKER_EXEC run --name keepalived --security-opt label=disable \
        --restart=unless-stopped "${KEEPALIVED_OPTIONS[@]}" \
        local-keepalived -- \
        keepalived --dont-fork --log-console -f /etc/keepalived/keepalived.conf \
    | tee -p "$SYSTEMD_CONTAINER_DIR/keepalived.container"
else
  $DOCKER_EXEC run -d --name keepalived --security-opt label=disable \
    --restart=unless-stopped "${KEEPALIVED_OPTIONS[@]}" \
    local-keepalived \
    keepalived --dont-fork --log-console -f /etc/keepalived/keepalived.conf

  if [[ $? -ne 0 ]]; then
    echo "Failed to run keepalived"
    exit 1
  fi

  podman generate systemd keepalived | tee -p "$SYSTEMD_SERVICE_DIR/keepalived.service"
  podman container stop keepalived
fi

if [[ "$SYSTEMD_SERVICE_DIR" == "/lib/systemd/system" ]]; then
  systemctl daemon-reload
else
  systemctl --user daemon-reload
fi

if [[ "$SYSTEMD_SERVICE_DIR" == "/lib/systemd/system" ]]; then
  if [[ $FIND_PODLET_RESULT -ne 0 ]]; then
    systemctl enable keepalived.service
  fi
  systemctl start keepalived.service
else
  if [[ $FIND_PODLET_RESULT -ne 0 ]]; then
    systemctl --user enable keepalived.service
  fi
  systemctl --user start keepalived.service
fi

if [[ "x$KEA_UPDATE" != "x" ]] || [[ "x$ROUTER_IMAGE_UPDATE" != "x" ]]; then
  podman image prune -a -f --filter "until=240h"
fi
