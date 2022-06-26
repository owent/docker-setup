#!/bin/bash

if [[ -e "/opt/nftables/sbin" ]]; then
  export PATH=/opt/nftables/sbin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/bin/site_perl:/usr/bin/vendor_perl:/usr/bin/core_perl
else
  export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/bin/site_perl:/usr/bin/vendor_perl:/usr/bin/core_perl
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [[ "x$ROUTER_HOME" == "x" ]] && [[ -e "$SCRIPT_DIR/../configure-router.sh" ]]; then
  source "$SCRIPT_DIR/../configure-router.sh"
fi
mkdir -p "$ROUTER_LOG_ROOT_DIR/samba"

# Require net.ipv4.ip_unprivileged_port_start=80 in /etc/sysctl.d/*.conf
# See https://github.com/containers/podman/blob/master/rootless.md

if [[ "root" == "$(id -un)" ]]; then
  SYSTEMD_SERVICE_DIR=/lib/systemd/system
else
  SYSTEMD_SERVICE_DIR="$HOME/.config/systemd/user"
  mkdir -p "$SYSTEMD_SERVICE_DIR"
fi

if [[ "$SYSTEMD_SERVICE_DIR" == "/lib/systemd/system" ]]; then
  systemctl --all | grep -F router-samba.service >/dev/null 2>&1
  if [ $? -eq 0 ]; then
    systemctl stop router-samba.service
    systemctl disable router-samba.service
  fi
else
  export XDG_RUNTIME_DIR="/run/user/$UID"
  export DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR}/bus"

  # Maybe need run from host: loginctl enable-linger tools
  # see https://wiki.archlinux.org/index.php/Systemd/User
  # sudo loginctl enable-linger $RUN_USER
  systemctl --user --all | grep -F router-samba.service >/dev/null 2>&1
  if [ $? -eq 0 ]; then
    systemctl --user stop router-samba.service
    systemctl --user disable router-samba.service
  fi
fi

podman container inspect router-samba >/dev/null 2>&1
if [[ $? -eq 0 ]]; then
  podman stop router-samba
  podman rm -f router-samba
fi

if [[ "x$SAMBA_UPDATE" != "x" ]] || [[ "x$ROUTER_IMAGE_UPDATE" != "x" ]]; then
  podman image inspect router-samba >/dev/null 2>&1
  if [[ $? -eq 0 ]]; then
    podman image rm -f router-samba
  fi
fi

podman build -t router-samba -f Dockerfile .

podman run -d --name=router-samba \
  -v $SAMBA_DATA_DIR:/data/content \
  -v $ROUTER_LOG_ROOT_DIR/samba:/data/logs \
  -p 139:139/TCP -p 445:445/TCP -p 137:137/UDP -p 138:138/UDP \
  --security-opt seccomp=unconfined \
  --security-opt label=disable \
  --mount type=tmpfs,target=/run,tmpfs-mode=1777,tmpfs-size=67108864 \
  --mount type=tmpfs,target=/run/lock,tmpfs-mode=1777,tmpfs-size=67108864 \
  --mount type=tmpfs,target=/tmp,tmpfs-mode=1777 \
  --mount type=tmpfs,target=/var/log/journal,tmpfs-mode=1777 \
  --mount type=bind,source=/sys/fs/cgroup,target=/sys/fs/cgroup \
  router-samba

# podman-compose up -f docker-compose.yml -d

if [[ $? -ne 0 ]]; then
  exit $?
fi

podman generate systemd router-samba | tee -p "$SYSTEMD_SERVICE_DIR/router-samba.service"
podman container stop router-samba

if [[ "$SYSTEMD_SERVICE_DIR" == "/lib/systemd/system" ]]; then
  systemctl enable router-samba.service
  systemctl daemon-reload
  systemctl start router-samba.service
else
  systemctl --user enable "$SYSTEMD_SERVICE_DIR/router-samba.service"
  systemctl --user daemon-reload
  systemctl --user start router-samba.service
fi
