#!/bin/bash

# Maybe need in /etc/ssh/sshd_config
#     DenyUsers tools
#     DenyGroups tools

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
source "$(dirname "$SCRIPT_DIR")/configure-router.sh"

if [[ "x$RUN_USER" == "x" ]]; then
  RUN_USER=$(id -un)
fi

if [[ "x$RUN_HOME" == "x" ]]; then
  RUN_HOME="$HOME"
fi

if [[ "x$RUN_HOME" == "x" ]]; then
  RUN_HOME=$(cat /etc/passwd | awk "BEGIN{FS=\":\"} \$1 == \"$RUN_USER\" { print \$6 }")
fi

if [[ "x$COREDNS_DNS_PORT" == "x" ]]; then
  COREDNS_DNS_PORT=53
fi

# root and NET_ADMIN is required to access ipset and nftables
if [[ "root" == "$(id -un)" ]]; then
  COREDNS_NETWORK_OPTIONS=(--cap-add=NET_ADMIN --cap-add=NET_RAW --network=host)
  SYSTEMD_SERVICE_DIR=/lib/systemd/system
else
  COREDNS_NETWORK_OPTIONS=(--cap-add=NET_BIND_SERVICE -p $COREDNS_DNS_PORT:$COREDNS_DNS_PORT/tcp -p $COREDNS_DNS_PORT:$COREDNS_DNS_PORT/udp -p 9153:9153/tcp)
  SYSTEMD_SERVICE_DIR="$HOME/.config/systemd/user"
  mkdir -p "$SYSTEMD_SERVICE_DIR"
fi

if [[ "x$COREDNS_ETC_DIR" == "x" ]]; then
  export COREDNS_ETC_DIR="$RUN_HOME/coredns/etc"
fi
mkdir -p "$COREDNS_ETC_DIR"

if [[ "x$COREDNS_UPDATE" != "x" ]] || [[ "x$ROUTER_IMAGE_UPDATE" != "x" ]]; then
  podman pull docker.io/owt5008137/coredns:latest
fi

if [[ "$SYSTEMD_SERVICE_DIR" == "/lib/systemd/system" ]]; then
  systemctl --all | grep -F coredns.service >/dev/null 2>&1
  if [ $? -eq 0 ]; then
    systemctl stop coredns.service
    systemctl disable coredns.service
  fi
else
  export XDG_RUNTIME_DIR="/run/user/$UID"
  export DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR}/bus"

  # Maybe need run from host: loginctl enable-linger tools
  # see https://wiki.archlinux.org/index.php/Systemd/User
  # sudo loginctl enable-linger $RUN_USER
  systemctl --user --all | grep -F coredns.service >/dev/null 2>&1
  if [ $? -eq 0 ]; then
    systemctl --user stop coredns.service
    systemctl --user disable coredns.service
  fi
fi

podman container inspect coredns >/dev/null 2>&1
if [[ $? -eq 0 ]]; then
  podman stop coredns
  podman rm -f coredns
fi

if [[ "x$COREDNS_UPDATE" != "x" ]] || [[ "x$ROUTER_IMAGE_UPDATE" != "x" ]]; then
  podman image prune -a -f --filter "until=240h"
fi

bash "$SCRIPT_DIR/merge-configure.sh"

podman run -d --name coredns \
  --security-opt seccomp=unconfined \
  --mount type=bind,source=$COREDNS_ETC_DIR,target=/etc/coredns/ \
  ${COREDNS_NETWORK_OPTIONS[@]} \
  docker.io/owt5008137/coredns:latest \
  -dns.port=$COREDNS_DNS_PORT \
  -conf /etc/coredns/Corefile

podman generate systemd coredns \
  | sed "/ExecStart=/i ExecStartPost=$SCRIPT_DIR/setup-resolv.sh" \
  | sed "/ExecStop=/i ExecStopPost=$SCRIPT_DIR/restore-resolv.sh" \
  | sed "/PIDFile=/a TimeoutSec=90" \
  | tee "$SYSTEMD_SERVICE_DIR/coredns.service"

podman stop coredns

if [[ "$SYSTEMD_SERVICE_DIR" == "/lib/systemd/system" ]]; then
  systemctl daemon-reload
  systemctl enable coredns.service
  systemctl start coredns.service
else
  systemctl --user daemon-reload
  systemctl --user enable "$SYSTEMD_SERVICE_DIR/coredns.service"
  systemctl --user start coredns.service
fi
