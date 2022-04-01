#!/bin/bash

# Maybe need in /etc/ssh/sshd_config
#     DenyUsers tools
#     DenyGroups tools

if [[ -e "/opt/nftables/sbin" ]]; then
  export PATH=/opt/nftables/sbin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/bin/site_perl:/usr/bin/vendor_perl:/usr/bin/core_perl
else
  export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/bin/site_perl:/usr/bin/vendor_perl:/usr/bin/core_perl
fi

SCRIPT_DIR="$(
  cd "$(dirname "$0")"
  pwd
)"

if [[ "x$ROUTER_HOME" == "x" ]]; then
  source "$SCRIPT_DIR/../configure-router.sh"
fi

if [[ "x$RUN_USER" == "x" ]]; then
  RUN_USER=$(id -un)
fi
RUN_HOME=$(cat /etc/passwd | awk "BEGIN{FS=\":\"} \$1 == \"$RUN_USER\" { print \$6 }")

if [[ "x$RUN_HOME" == "x" ]]; then
  RUN_HOME="$HOME"
fi

if [[ "x$COREDNS_DNS_PORT" == "x" ]]; then
  COREDNS_DNS_PORT=53
fi

# root and NET_ADMIN is required to access ipset and nftables
if [[ "root" == "$(id -un)" ]]; then
  COREDNS_NETWORK_OPTIONS=(--cap-add=NET_ADMIN --cap-add=NET_RAW --network=host)
  SYSTEMD_SERVICE_DIR=/lib/systemd/system
else
  COREDNS_NETWORK_OPTIONS=(-p $COREDNS_DNS_PORT:$COREDNS_DNS_PORT/tcp -p $COREDNS_DNS_PORT:$COREDNS_DNS_PORT/udp)
  SYSTEMD_SERVICE_DIR="$HOME/.config/systemd/user"
  mkdir -p "$SYSTEMD_SERVICE_DIR"
fi

if [[ "x$COREDNS_ETC_DIR" == "x" ]]; then
  export COREDNS_ETC_DIR="$RUN_HOME/coredns/etc"
fi
mkdir -p "$COREDNS_ETC_DIR"

if [[ "x$COREDNS_LOG_DIR" == "x" ]]; then
  export COREDNS_LOG_DIR="$RUN_HOME/coredns/log"
fi
mkdir -p "$COREDNS_LOG_DIR"

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

if [[ "x$V2RAY_UPDATE" != "x" ]]; then
  podman image inspect docker.io/coredns/coredns:latest >/dev/null 2>&1
  if [[ $? -eq 0 ]]; then
    podman image rm -f docker.io/coredns/coredns:latest
  fi
fi

bash "$SCRIPT_DIR/merge-configure.sh"

podman run -d --name coredns \
  --security-opt seccomp=unconfined \
  --mount type=bind,source=$COREDNS_ETC_DIR,target=/etc/coredns/ \
  --mount type=bind,source=$COREDNS_LOG_DIR,target=/var/log/coredns/ \
  ${COREDNS_NETWORK_OPTIONS[@]} \
  docker.io/coredns/coredns:latest \
  -dns.port=$COREDNS_DNS_PORT \
  -conf /etc/coredns/Corefile \
  -log_dir /var/log/coredns

podman generate systemd coredns | tee "$SYSTEMD_SERVICE_DIR/coredns.service"

if [[ "$SYSTEMD_SERVICE_DIR" == "/lib/systemd/system" ]]; then
  systemctl daemon-reload
  systemctl enable coredns.service
  systemctl start coredns.service
else
  systemctl --user daemon-reload
  systemctl --user enable "$SYSTEMD_SERVICE_DIR/coredns.service"
  systemctl --user start coredns.service
fi