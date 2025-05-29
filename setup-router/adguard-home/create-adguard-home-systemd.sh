#!/bin/bash

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
source "$(dirname "$SCRIPT_DIR")/configure-router.sh"

export XDG_RUNTIME_DIR="/run/user/$UID"
export DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR}/bus"

if [[ "x$RUN_USER" == "x" ]]; then
    RUN_USER=$(id -un)
fi
RUN_HOME=$(cat /etc/passwd | awk "BEGIN{FS=\":\"} \$1 == \"$RUN_USER\" { print \$6 }")

if [[ "x$RUN_HOME" == "x" ]]; then
    RUN_HOME="$HOME"
fi
# ADGUARD_HOME_NETWORK=(host)
# ADGUARD_HOME_RUN_USER=(root)
if [[ -z "$ADGUARD_HOME_ETC_DIR" ]]; then
    ADGUARD_HOME_ETC_DIR="$SCRIPT_DIR/etc"
fi
mkdir -p "$ADGUARD_HOME_ETC_DIR"

if [[ -z "$ADGUARD_HOME_SSL_DIR" ]]; then
    ADGUARD_HOME_SSL_DIR="$SCRIPT_DIR/ssl"
fi
mkdir -p "$ADGUARD_HOME_SSL_DIR"

if [[ -z "$ADGUARD_HOME_DATA_DIR" ]]; then
    ADGUARD_HOME_DATA_DIR="$SCRIPT_DIR/data"
fi
mkdir -p "$ADGUARD_HOME_DATA_DIR"

if [[ -z "$ADGUARD_HOME_IMAGE" ]]; then
    ADGUARD_HOME_IMAGE="adguard/adguardhome:latest"
fi
if [[ "x$ADGUARD_HOME_UPDATE" != "x" ]] || [[ "x$ROUTER_IMAGE_UPDATE" != "x" ]]; then
    podman pull $ADGUARD_HOME_IMAGE
fi

systemctl --user --all | grep -F container-adguard-home.service

if [[ $? -eq 0 ]]; then
    systemctl --user stop container-adguard-home
    systemctl --user disable container-adguard-home
fi

podman container exists adguardhome >/dev/null 2>&1

if [[ $? -eq 0 ]]; then
    podman stop adguardhome
    podman rm -f adguardhome
fi

if [[ "x$REDIS_UPDATE" != "x" ]] || [[ "x$ROUTER_IMAGE_UPDATE" != "x" ]]; then
    podman image prune -a -f --filter "until=240h"
fi

ADGUARD_HOME_OPTIONS=(
    -e "TZ=Asia/Shanghai"
    --mount "type=bind,source=$ADGUARD_HOME_ETC_DIR,target=/opt/adguardhome/conf"
    --mount "type=bind,source=$ADGUARD_HOME_SSL_DIR,target=/opt/adguardhome/ssl"
    --mount "type=bind,source=$ADGUARD_HOME_DATA_DIR,target=/opt/adguardhome/work"
)
ADGUARD_HOME_HAS_HOST_NETWORK=0
if [[ ! -z "$ADGUARD_HOME_NETWORK" ]]; then
    for network in ${ADGUARD_HOME_NETWORK[@]}; do
        ADGUARD_HOME_OPTIONS+=("--network=$network")
        if [[ $network == "host" ]]; then
            ADGUARD_HOME_HAS_HOST_NETWORK=1
        fi
    done
fi
if [[ $ADGUARD_HOME_HAS_HOST_NETWORK -eq 0 ]]; then
    if [[ ! -z "$ADGUARD_HOME_PORT" ]]; then
        for bing_port in ${ADGUARD_HOME_PORT[@]}; do
            ADGUARD_HOME_OPTIONS+=(-p "$bing_port")
        done
    fi
fi

if [[ ! -z "$ADGUARD_HOME_RUN_USER" ]]; then
    ADGUARD_HOME_OPTIONS+=("--user=$ADGUARD_HOME_RUN_USER")
fi

podman run -d --name adguardhome --security-opt label=disable \
    "${ADGUARD_HOME_OPTIONS[@]}" \
    $ADGUARD_HOME_IMAGE

if [[ $? -ne 0 ]]; then
    echo "Error: Unable to start adguardhome container"
    exit 1
fi

podman stop adguardhome

podman generate systemd --name adguardhome | tee $ADGUARD_HOME_ETC_DIR/container-adguard-home.service

systemctl --user enable $ADGUARD_HOME_ETC_DIR/container-adguard-home.service
systemctl --user restart container-adguard-home
