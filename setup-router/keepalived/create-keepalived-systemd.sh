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
    # $DOCKER_EXEC pull docker.cloudsmith.io/isc/docker/kea-dhcp4:latest
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

systemctl --all | grep -F container-keepalived.service

if [[ $? -eq 0 ]]; then
    systemctl stop container-keepalived
    systemctl disable container-keepalived
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

$DOCKER_EXEC run -d --name keepalived --security-opt label=disable \
    --restart=unless-stopped "${KEEPALIVED_OPTIONS[@]}" \
    local-keepalived \
    keepalived --dont-fork --log-console -f /etc/keepalived/keepalived.conf

if [[ $? -ne 0 ]]; then
    echo "Error: Unable to start keepalived container"
    exit 1
fi

if [[ "$$DOCKER_EXEC" == "podman" ]]; then
    podman stop keepalived

    podman generate systemd --name keepalived | tee $KEEPALIVED_ETC_DIR/container-keepalived.service

    systemctl enable $KEEPALIVED_ETC_DIR/container-keepalived.service
    systemctl restart container-keepalived
fi
