#!/bin/bash

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"

if [[ "$(id -n -u)" != "root" ]]; then
  echo -e "\033[1;32mkea must run as root to obtain NET_RAW\033[0m"
  exit 1
fi

if [[ -e "$SCRIPT_DIR/../configure-router.sh" ]]; then
  source "$SCRIPT_DIR/../configure-router.sh"
fi

if [[ "x$KEA_ETC_DIR" == "x" ]]; then
  KEA_ETC_DIR="$SCRIPT_DIR/etc"
fi
mkdir -p "$KEA_ETC_DIR"

if [[ "x$KEA_DATA_DIR" == "x" ]]; then
  KEA_DATA_DIR="$SCRIPT_DIR/data"
fi
mkdir -p "$KEA_DATA_DIR"

if [[ ! -e "$KEA_ETC_DIR/kea-ctrl-agent.conf" ]] && [[ -e "$SCRIPT_DIR/kea-ctrl-agent.conf" ]]; then
  cp -f "$SCRIPT_DIR/kea-ctrl-agent.conf" "$KEA_ETC_DIR/kea-ctrl-agent.conf"
fi

KEA_OPTIONS=(
  --cap-add NET_BIND_SERVICE --cap-add NET_RAW
  --cap-add NET_ADMIN --cap-add NET_BROADCAST
  --security-opt label=disable --security-opt seccomp=unconfined
  --network=host
  --mount type=bind,source=$KEA_ETC_DIR,target=/etc/kea
  --mount type=bind,source=$KEA_DATA_DIR,target=/var/lib/kea
  --mount type=tmpfs,target=/run,tmpfs-mode=1777,tmpfs-size=16777216
  --mount type=tmpfs,target=/run/lock,tmpfs-mode=1777,tmpfs-size=16777216
  --mount type=tmpfs,target=/run/kea,tmpfs-mode=1750,tmpfs-size=16777216
  --mount type=tmpfs,target=/tmp,tmpfs-mode=1777
)

if [[ -n "$ACMESH_SSL_DIR" ]]; then
  KEA_OPTIONS+=(--mount type=bind,source="$ACMESH_SSL_DIR",target=$ACMESH_SSL_DIR,readonly)
fi

if [[ -n "$HOME_CERTS_SSL_DIR" ]]; then
  KEA_OPTIONS+=(--mount type=bind,source="$HOME_CERTS_SSL_DIR",target=$HOME_CERTS_SSL_DIR,readonly)
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

systemctl --all | grep -F kea-ctrl-agent.service >/dev/null 2>&1
if [ $? -eq 0 ]; then
  systemctl stop kea-ctrl-agent.service
  systemctl disable kea-ctrl-agent.service
fi

podman image inspect local-kea >/dev/null 2>&1 || KEA_UPDATE=1
if [[ "x$KEA_UPDATE" != "x" ]] || [[ "x$ROUTER_IMAGE_UPDATE" != "x" ]]; then
  podman pull alpine:latest
  if [[ $? -ne 0 ]]; then
    exit 1
  fi

  podman build --network=host --tag local-kea -f kea.Dockerfile .
  if [[ $? -ne 0 ]]; then
    exit 1
  fi
fi

podman inspect kea-ctrl-agent >/dev/null 2>&1
if [[ $? -eq 0 ]]; then
  podman stop kea-ctrl-agent || true
  podman rm kea-ctrl-agent || true
fi

if [[ "x$KEA_UPDATE" != "x" ]] || [[ "x$ROUTER_IMAGE_UPDATE" != "x" ]]; then
  podman image prune -a -f --filter "until=240h"
fi

PODLET_IMAGE_URL="ghcr.io/containers/podlet:latest"
PODLET_RUN=($(which podlet 2>/dev/null))
FIND_PODLET_RESULT=$?
if [[ $FIND_PODLET_RESULT -ne 0 ]]; then
  (podman image inspect "$PODLET_IMAGE_URL" > /dev/null 2>&1 || podman pull "$PODLET_IMAGE_URL") && FIND_PODLET_RESULT=0 && PODLET_RUN=(podman run --rm "$PODLET_IMAGE_URL")
fi

KEA_EXEC_RELOAD="ExecReload=/bin/bash -c '$(which podman) kill --signal HUP kea-ctrl-agent'"
if [[ $FIND_PODLET_RESULT -eq 0 ]]; then
  PODLET_OPTIONS=(--install --wanted-by default.target --wants network-online.target --after network-online.target)
  
  ${PODLET_RUN[@]} "${PODLET_OPTIONS[@]}" \
    podman run -d --name kea-ctrl-agent "${KEA_OPTIONS[@]}" \
      local-kea -- /usr/sbin/kea-ctrl-agent -c /etc/kea/kea-ctrl-agent.conf  | \
      sed "/\\[Install/i [Service]\n$KEA_EXEC_RELOAD" | \
      tee -p "$SYSTEMD_CONTAINER_DIR/kea-ctrl-agent.container"
else
  podman run -d --name kea-ctrl-agent "${KEA_OPTIONS[@]}" \
    local-kea /usr/sbin/kea-ctrl-agent -c /etc/kea/kea-ctrl-agent.conf

  if [[ $? -ne 0 ]]; then
    echo "Failed to run kea-ctrl-agent"
    exit 1
  fi

  podman generate systemd kea-ctrl-agent | \
    sed "/ExecReload=/d" | \
    sed "/ExecStart=/a $KEA_EXEC_RELOAD" | \
    tee -p "$SYSTEMD_SERVICE_DIR/kea-ctrl-agent.service"
  podman container stop kea-ctrl-agent
fi

if [[ "$SYSTEMD_SERVICE_DIR" == "/lib/systemd/system" ]]; then
  systemctl daemon-reload
else
  systemctl --user daemon-reload
fi

if [[ "$SYSTEMD_SERVICE_DIR" == "/lib/systemd/system" ]]; then
  if [[ $FIND_PODLET_RESULT -ne 0 ]]; then
    systemctl enable kea-ctrl-agent.service
  fi
  systemctl start kea-ctrl-agent.service
else
  if [[ $FIND_PODLET_RESULT -ne 0 ]]; then
    systemctl --user enable kea-ctrl-agent.service
  fi
  systemctl --user start kea-ctrl-agent.service
fi

if [[ "x$KEA_UPDATE" != "x" ]] || [[ "x$ROUTER_IMAGE_UPDATE" != "x" ]]; then
  podman image prune -a -f --filter "until=240h"
fi

