#!/bin/bash

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
source "$(dirname "$SCRIPT_DIR")/configure-router.sh"

if [[ "root" != "$(id -un)" ]]; then
  export XDG_RUNTIME_DIR="/run/user/$UID"
  export DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR}/bus"
fi

if ! command -v podman >/dev/null 2>&1; then
  echo "Error: podman is required to create smartdns service."
  exit 1
fi

if [[ "x$RUN_USER" == "x" ]]; then
  RUN_USER=$(id -un)
fi
RUN_HOME=$(awk -F: -v user="$RUN_USER" '$1 == user { print $6 }' /etc/passwd)

if [[ "x$RUN_HOME" == "x" ]]; then
  RUN_HOME="$HOME"
fi

SMARTDNS_NETWORK=(host)

if [[ "x$SMARTDNS_DNS_PORT" == "x" ]]; then
  SMARTDNS_DNS_PORT=53
fi
if [[ "x$SMARTDNS_IPV6_SERVER" == "x" ]]; then
  SMARTDNS_IPV6_SERVER=1
fi
if [[ "x$SMARTDNS_WEBUI_ENABLE" == "x" ]]; then
  SMARTDNS_WEBUI_ENABLE=1
fi
if [[ "x$SMARTDNS_WEBUI_PORT" == "x" ]]; then
  SMARTDNS_WEBUI_PORT=6080
fi
if [[ "x$SMARTDNS_WEBUI_USER" == "x" ]]; then
  SMARTDNS_WEBUI_USER=admin
fi
if [[ "x$SMARTDNS_WEBUI_PASSWORD" == "x" ]]; then
  SMARTDNS_WEBUI_PASSWORD=change-this-password
fi
if [[ "x$SMARTDNS_IMAGE" == "x" ]]; then
  SMARTDNS_IMAGE="docker.io/pymumu/smartdns:latest"
fi

if [[ "x$SMARTDNS_BIND_ADDRESS" == "x" ]]; then
  if [[ $SMARTDNS_IPV6_SERVER -ne 0 ]]; then
    SMARTDNS_BIND_ADDRESS="[::]:$SMARTDNS_DNS_PORT"
  else
    SMARTDNS_BIND_ADDRESS=":$SMARTDNS_DNS_PORT"
  fi
fi

if [[ "x$SMARTDNS_WEBUI_LISTEN" == "x" ]]; then
  if [[ $SMARTDNS_IPV6_SERVER -ne 0 ]]; then
    SMARTDNS_WEBUI_LISTEN="http://[::]:$SMARTDNS_WEBUI_PORT"
  else
    SMARTDNS_WEBUI_LISTEN="http://0.0.0.0:$SMARTDNS_WEBUI_PORT"
  fi
fi

if [[ "x$SMARTDNS_ETC_DIR" == "x" ]]; then
  export SMARTDNS_ETC_DIR="$SCRIPT_DIR/smartdns-etc"
fi
mkdir -p "$SMARTDNS_ETC_DIR"

if [[ "x$SMARTDNS_DATA_DIR" == "x" ]]; then
  export SMARTDNS_DATA_DIR="$SCRIPT_DIR/smartdns-data"
fi
mkdir -p "$SMARTDNS_DATA_DIR"
mkdir -p "$SMARTDNS_DATA_DIR/cache"

if [[ "x$SMARTDNS_RESOLV_CONF" == "x" ]]; then
  if [[ -e "$SMARTDNS_ETC_DIR/resolv.conf" ]]; then
    SMARTDNS_RESOLV_CONF="$SMARTDNS_ETC_DIR/resolv.conf"
  else
    SMARTDNS_RESOLV_CONF="/etc/resolv.conf"
  fi
fi

if [[ ! -e "$SMARTDNS_RESOLV_CONF" ]]; then
  echo "Error: SMARTDNS_RESOLV_CONF not found: $SMARTDNS_RESOLV_CONF"
  exit 1
fi

mkdir -p "$SMARTDNS_ETC_DIR/generated.d"

if [[ ! -e "$SMARTDNS_ETC_DIR/generated.d/00-generated-placeholder.conf" ]]; then
  cat >"$SMARTDNS_ETC_DIR/generated.d/00-generated-placeholder.conf" <<'EOF'
# Generated runtime smartdns rules are written into this directory.
EOF
fi

SMARTDNS_OUTPUT_CONF="$SMARTDNS_ETC_DIR/smartdns.conf"

cat >"$SMARTDNS_OUTPUT_CONF" <<EOF
bind $SMARTDNS_BIND_ADDRESS
bind-tcp $SMARTDNS_BIND_ADDRESS
server-name $ROUTER_DOMAIN
data-dir /var/lib/smartdns
EOF

if [[ $SMARTDNS_WEBUI_ENABLE -ne 0 ]]; then
  cat >>"$SMARTDNS_OUTPUT_CONF" <<EOF
plugin smartdns_ui.so
smartdns-ui.www-root /usr/share/smartdns/wwwroot
smartdns-ui.ip $SMARTDNS_WEBUI_LISTEN
smartdns-ui.token-expire 600
smartdns-ui.max-query-log-age 2592000
smartdns-ui.enable-terminal no
smartdns-ui.enable-cors no
smartdns-ui.user $SMARTDNS_WEBUI_USER
smartdns-ui.password $SMARTDNS_WEBUI_PASSWORD
EOF
fi

while IFS= read -r config_file; do
  if [[ "$config_file" == "$SMARTDNS_OUTPUT_CONF" ]]; then
    continue
  fi
  printf '\n' >>"$SMARTDNS_OUTPUT_CONF"
  cat "$config_file" >>"$SMARTDNS_OUTPUT_CONF"
done < <(find "$SMARTDNS_ETC_DIR" -maxdepth 1 -type f -name '*.conf' | sort)

if [[ "x$SMARTDNS_APPEND_CONFIGURE" != "x" ]]; then
  printf '\n%s\n' "$SMARTDNS_APPEND_CONFIGURE" >>"$SMARTDNS_OUTPUT_CONF"
fi

podman image inspect "$SMARTDNS_IMAGE" >/dev/null 2>&1
if [[ $? -ne 0 ]]; then
  SMARTDNS_UPDATE=1
fi

if [[ "x$SMARTDNS_UPDATE" != "x" ]] || [[ "x$ROUTER_IMAGE_UPDATE" != "x" ]]; then
  podman pull "$SMARTDNS_IMAGE"
  if [[ $? -ne 0 ]]; then
    echo "Error: Unable to pull $SMARTDNS_IMAGE"
    exit 1
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
  echo "Warning: rootless smartdns containers cannot update ipset/nftset. Run this script as root when you need nftables integration."
fi

if [[ "$SYSTEMD_SERVICE_DIR" == "/lib/systemd/system" ]] || [[ "$SYSTEMD_SERVICE_DIR" == "/usr/lib/systemd/system" ]] || [[ "$SYSTEMD_SERVICE_DIR" == "/etc/systemd/system" ]]; then
  systemctl --all | grep -F smartdns.service >/dev/null 2>&1
  if [[ $? -eq 0 ]]; then
    systemctl stop smartdns.service
    systemctl disable smartdns.service
  fi
else
  systemctl --user --all | grep -F smartdns.service >/dev/null 2>&1
  if [[ $? -eq 0 ]]; then
    systemctl --user stop smartdns.service
    systemctl --user disable smartdns.service
  fi
fi

podman container exists smartdns >/dev/null 2>&1
if [[ $? -eq 0 ]]; then
  podman stop smartdns
  podman rm -f smartdns
fi

rm -f "$SYSTEMD_CONTAINER_DIR/smartdns.container"
rm -f "$SYSTEMD_SERVICE_DIR/smartdns.service"

if [[ "x$SMARTDNS_UPDATE" != "x" ]] || [[ "x$ROUTER_IMAGE_UPDATE" != "x" ]]; then
  podman image prune -a -f --filter "until=240h"
fi

SMARTDNS_OPTIONS=(
  --security-opt label=disable
  -e "TZ=Asia/Shanghai"
  --mount "type=bind,source=$SMARTDNS_ETC_DIR,target=/etc/smartdns"
  --mount "type=bind,source=$SMARTDNS_DATA_DIR,target=/var/lib/smartdns"
  -v "$SMARTDNS_RESOLV_CONF:/etc/resolv.conf:ro"
)
SMARTDNS_HAS_HOST_NETWORK=0

if [[ "root" == "$(id -un)" ]]; then
  SMARTDNS_OPTIONS+=(--cap-add=NET_ADMIN --cap-add=NET_RAW)
  if [[ ${#SMARTDNS_NETWORK[@]} -eq 0 ]]; then
    SMARTDNS_NETWORK=(host)
  fi
fi

if [[ ${#SMARTDNS_NETWORK[@]} -gt 0 ]]; then
  for network in ${SMARTDNS_NETWORK[@]}; do
    SMARTDNS_OPTIONS+=("--network=$network")
    if [[ "$network" == "host" ]]; then
      SMARTDNS_HAS_HOST_NETWORK=1
    fi
  done
fi

if [[ $SMARTDNS_HAS_HOST_NETWORK -eq 0 ]]; then
  if [[ ${#SMARTDNS_PORT[@]} -gt 0 ]]; then
    for bind_port in ${SMARTDNS_PORT[@]}; do
      SMARTDNS_OPTIONS+=(-p "$bind_port")
    done
  else
    SMARTDNS_OPTIONS+=(-p "$SMARTDNS_DNS_PORT:$SMARTDNS_DNS_PORT/tcp")
    SMARTDNS_OPTIONS+=(-p "$SMARTDNS_DNS_PORT:$SMARTDNS_DNS_PORT/udp")
    if [[ $SMARTDNS_WEBUI_ENABLE -ne 0 ]]; then
      SMARTDNS_OPTIONS+=(-p "$SMARTDNS_WEBUI_PORT:$SMARTDNS_WEBUI_PORT/tcp")
    fi
  fi
fi

PODLET_IMAGE_URL="ghcr.io/containers/podlet:latest"
PODLET_RUN=(podlet)
FIND_PODLET_RESULT=0
if ! command -v podlet >/dev/null 2>&1; then
  FIND_PODLET_RESULT=1
  if podman image inspect "$PODLET_IMAGE_URL" >/dev/null 2>&1 || podman pull "$PODLET_IMAGE_URL" >/dev/null 2>&1; then
    PODLET_RUN=(podman run --rm "$PODLET_IMAGE_URL")
    FIND_PODLET_RESULT=0
  fi
fi

if [[ $FIND_PODLET_RESULT -eq 0 ]]; then
  PODLET_OPTIONS=(--install --wanted-by default.target --wants network-online.target --after network-online.target)
  ${PODLET_RUN[@]} "${PODLET_OPTIONS[@]}" \
    podman run -d --name smartdns \
      "${SMARTDNS_OPTIONS[@]}" \
      "$SMARTDNS_IMAGE" | tee "$SYSTEMD_CONTAINER_DIR/smartdns.container"
else
  podman run -d --name smartdns \
    "${SMARTDNS_OPTIONS[@]}" \
    "$SMARTDNS_IMAGE"
  podman generate systemd smartdns | tee "$SYSTEMD_SERVICE_DIR/smartdns.service"
  podman container stop smartdns
fi

if [[ "$SYSTEMD_SERVICE_DIR" == "/lib/systemd/system" ]] || [[ "$SYSTEMD_SERVICE_DIR" == "/usr/lib/systemd/system" ]] || [[ "$SYSTEMD_SERVICE_DIR" == "/etc/systemd/system" ]]; then
  systemctl daemon-reload
else
  systemctl --user daemon-reload
fi

if [[ "$SYSTEMD_SERVICE_DIR" == "/lib/systemd/system" ]] || [[ "$SYSTEMD_SERVICE_DIR" == "/usr/lib/systemd/system" ]] || [[ "$SYSTEMD_SERVICE_DIR" == "/etc/systemd/system" ]]; then
  if [[ $FIND_PODLET_RESULT -ne 0 ]]; then
    systemctl enable smartdns.service
  fi
  systemctl start smartdns.service
else
  if [[ $FIND_PODLET_RESULT -ne 0 ]]; then
    systemctl --user enable smartdns.service
  fi
  systemctl --user start smartdns.service
fi

if [[ "x$SMARTDNS_UPDATE" != "x" ]] || [[ "x$ROUTER_IMAGE_UPDATE" != "x" ]]; then
  podman image prune -a -f --filter "until=240h"
fi
