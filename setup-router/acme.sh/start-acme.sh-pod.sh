#!/bin/bash

if [ -e "/opt/nftables/sbin" ]; then
  export PATH=/opt/nftables/sbin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/bin/site_perl:/usr/bin/vendor_perl:/usr/bin/core_perl
else
  export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/bin/site_perl:/usr/bin/vendor_perl:/usr/bin/core_perl
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [[ "x$ROUTER_HOME" == "x" ]] && [[ -e "$SCRIPT_DIR/../configure-router.sh" ]]; then
  source "$SCRIPT_DIR/../configure-router.sh"
fi

if [[ "x$ACMESH_SSL_DIR" == "x" ]]; then
  if [[ "x$ROUTER_HOME" != "x" ]]; then
    ACMESH_SSL_DIR=$ROUTER_HOME/acme.sh/ssl
  else
    ACMESH_SSL_DIR="$HOME/acme.sh/ssl"
  fi
fi
mkdir -p "$ACMESH_SSL_DIR"

# Require net.ipv4.ip_unprivileged_port_start=80 in /etc/sysctl.d/*.conf
# See https://github.com/containers/podman/blob/master/rootless.md

if [[ "root" == "$(id -un)" ]]; then
  SYSTEMD_SERVICE_DIR=/lib/systemd/system
else
  SYSTEMD_SERVICE_DIR="$HOME/.config/systemd/user"
  mkdir -p "$SYSTEMD_SERVICE_DIR"
fi

if [[ "$SYSTEMD_SERVICE_DIR" == "/lib/systemd/system" ]]; then
  systemctl --all | grep -F acme.sh.service >/dev/null 2>&1
  if [ $? -eq 0 ]; then
    systemctl stop acme.sh.service
    systemctl disable acme.sh.service
  fi
else
  export XDG_RUNTIME_DIR="/run/user/$UID"
  export DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR}/bus"

  # Maybe need run from host: loginctl enable-linger tools
  # see https://wiki.archlinux.org/index.php/Systemd/User
  # sudo loginctl enable-linger $RUN_USER
  systemctl --user --all | grep -F acme.sh.service >/dev/null 2>&1
  if [ $? -eq 0 ]; then
    systemctl --user stop acme.sh.service
    systemctl --user disable acme.sh.service
  fi
fi

podman container inspect acme.sh >/dev/null 2>&1
if [[ $? -eq 0 ]]; then
  podman stop acme.sh
  podman rm -f acme.sh
fi

if [[ "x$ACMESH_UPDATE" != "x" ]]; then
  podman image inspect docker.io/neilpang/acme.sh:latest >/dev/null 2>&1
  if [[ $? -eq 0 ]]; then
    podman image rm -f docker.io/neilpang/acme.sh:latest
  fi
fi

podman pull docker.io/neilpang/acme.sh:latest

podman run -d --name acme.sh --security-opt label=disable \
  --mount type=bind,source=$ACMESH_SSL_DIR,target=/acme.sh \
  --network=host \
  docker.io/neilpang/acme.sh:latest daemon

# Some system with old slirp4netns do not work, debian 10 for example, so we use --network=host here
# -p 80:80/tcp -p 80:80/udp -p 443:443/tcp -p 443:443/udp                                    \
if [[ $? -ne 0 ]]; then
  exit $?
fi

podman generate systemd acme.sh | tee -p "$SYSTEMD_SERVICE_DIR/acme.sh.service"
podman container stop acme.sh

if [[ "$SYSTEMD_SERVICE_DIR" == "/lib/systemd/system" ]]; then
  systemctl enable acme.sh.service
  systemctl daemon-reload
  systemctl start acme.sh.service
else
  systemctl --user enable "$SYSTEMD_SERVICE_DIR/acme.sh.service"
  systemctl --user daemon-reload
  systemctl --user start acme.sh.service
fi
