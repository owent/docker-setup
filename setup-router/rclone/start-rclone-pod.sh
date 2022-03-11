#!/bin/bash

if [[ -e "/opt/nftables/sbin" ]]; then
  export PATH=/opt/nftables/sbin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/bin/site_perl:/usr/bin/vendor_perl:/usr/bin/core_perl
else
  export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/bin/site_perl:/usr/bin/vendor_perl:/usr/bin/core_perl
fi

export XDG_RUNTIME_DIR="/run/user/$UID"
export DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR}/bus"

RUN_USER=$(whoami)
# sudo loginctl enable-linger $RUN_USER

if [[ "x$RUN_USER" == "x" ]] || [[ "x$RUN_USER" == "xroot" ]]; then
  echo -e "\033[1;32m$0 can not run with\033[0;m \033[1;31m$RUN_USER\033[0;m"
  exit 1
fi

RUN_HOME=$(cat /etc/passwd | awk "BEGIN{FS=\":\"} \$1 == \"$RUN_USER\" { print \$6 }")

if [[ "x$RUN_HOME" == "x" ]]; then
  RUN_HOME="$HOME"
fi

if [[ "x$RCLONE_ETC_DIR" == "x" ]]; then
  RCLONE_ETC_DIR="$RUN_HOME/rclone/etc"
fi
mkdir -p "$RCLONE_ETC_DIR"

if [[ "x$RCLONE_DATA_DIR" == "x" ]]; then
  RCLONE_DATA_DIR="$RUN_HOME/rclone/data"
fi
mkdir -p "$RCLONE_DATA_DIR"

if [[ "x$RCLONE_UPDATE" != "x" ]]; then
  podman image inspect docker.io/rclone/rclone:latest >/dev/null 2>&1
  if [[ $? -eq 0 ]]; then
    podman image rm -f docker.io/rclone/rclone:latest
  fi
fi

podman pull docker.io/rclone/rclone:latest

# See https://rclone.org/install/
# See https://rclone.org/onedrive/

# podman run -it --network=host --security-opt seccomp=unconfined --rm    \
#     --volume $HOME/rclone/etc:/config/rclone                            \
#     --volume $HOME/rclone/data:/data:shared                             \
#     --user $(id -u):$(id -g)                                            \
#     --volume /etc/passwd:/etc/passwd:ro                                 \
#     --volume /etc/group:/etc/group:ro                                   \
#     --device /dev/fuse --cap-add SYS_ADMIN                              \
#     docker.io/rclone/rclone config

podman run --rm --security-opt seccomp=unconfined \
  --mount type=bind,source=$RCLONE_ETC_DIR,target=/config/rclone,ro=true \
  --mount type=bind,source=$RCLONE_DATA_DIR,target=/data:shared \
  --mount type=bind,source=$RUN_HOME/bitwarden/data,target=/data/bitwarden/data \
  --device /dev/fuse --cap-add SYS_ADMIN --network=host \
  docker.io/rclone/rclone:latest \
  sync --progress /data remote-onedrive:/Apps/OWenT.Home.rclone
# --copy-links
