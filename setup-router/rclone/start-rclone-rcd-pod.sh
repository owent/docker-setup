#!/bin/bash

if [[ -e "/opt/nftables/sbin" ]]; then
  export PATH=/opt/nftables/sbin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/bin/site_perl:/usr/bin/vendor_perl:/usr/bin/core_perl
else
  export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/bin/site_perl:/usr/bin/vendor_perl:/usr/bin/core_perl
fi

export XDG_RUNTIME_DIR="/run/user/$UID"
export DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR}/bus"

RUN_USER=$(id -un)
# sudo loginctl enable-linger $RUN_USER

if [[ "x$RUN_USER" == "x" ]] || [[ "x$RUN_USER" == "xroot" ]]; then
  echo -e "\033[1;32m$0 can not run with\033[0;m \033[1;31m$RUN_USER\033[0;m"
  exit 1
fi

RUN_HOME=$(cat /etc/passwd | awk "BEGIN{FS=\":\"} \$1 == \"$RUN_USER\" { print \$6 }")

if [[ "x$RUN_HOME" == "x" ]]; then
  RUN_HOME="$HOME"
fi

if [[ "x$RCLONE_LISTEN_PORT" == "x" ]]; then
  RCLONE_LISTEN_PORT=:5572
fi

if [[ "x$RCLONE_ETC_DIR" == "x" ]]; then
  RCLONE_ETC_DIR="$RUN_HOME/rclone/etc"
fi
mkdir -p "$RCLONE_ETC_DIR"

if [[ "x$RCLONE_DATA_DIR" == "x" ]]; then
  RCLONE_DATA_DIR="$RUN_HOME/rclone/data"
fi
mkdir -p "$RCLONE_DATA_DIR"

if [[ "x" == "x$ADMIN_USENAME" ]]; then
  ADMIN_USENAME=owent
fi
if [[ "x" == "x$ADMIN_TOKEN" ]]; then
  ADMIN_TOKEN=$(openssl rand -base64 48)
fi
echo "$ADMIN_USENAME $ADMIN_TOKEN" | tee "$RCLONE_ETC_DIR/admin-access"

systemctl --user --all | grep -F container-rclone-rcd.service

if [[ $? -eq 0 ]]; then
  systemctl --user stop container-rclone-rcd
  systemctl --user disable container-rclone-rcd
fi

podman container inspect rclone-rcd >/dev/null 2>&1

if [[ $? -eq 0 ]]; then
  podman stop rclone-rcd
  podman rm -f rclone-rcd
fi

if [[ "x$RCLONE_UPDATE" != "x" ]] || [[ "x$ROUTER_IMAGE_UPDATE" != "x" ]]; then
  podman image prune -f
  podman pull docker.io/rclone/rclone:latest
fi

# See https://rclone.org/install/
# See https://rclone.org/onedrive/

# podman run -it --network=host --security-opt seccomp=unconfined --rm    \
#     --volume $HOME/rclone/etc:/config/rclone                            \
#     --volume $HOME/rclone/data:/data:rw                                 \
#     --user $(id -u):$(id -g)                                            \
#     --volume /etc/passwd:/etc/passwd:ro                                 \
#     --volume /etc/group:/etc/group:ro                                   \
#     --device /dev/fuse --cap-add SYS_ADMIN                              \
#     docker.io/rclone/rclone config

podman run -d --name rclone-rcd --security-opt seccomp=unconfined \
  --mount type=bind,source=$RCLONE_ETC_DIR,target=/config/rclone \
  --mount type=bind,source=$RCLONE_DATA_DIR,target=/data:rw \
  --device /dev/fuse --cap-add SYS_ADMIN --network=host \
  docker.io/rclone/rclone:latest \
  rcd --log-systemd --rc-web-gui --rc-web-gui-no-open-browser --rc-user $ADMIN_USENAME --rc-pass $ADMIN_TOKEN --rc-serve --rc-addr $RCLONE_LISTEN_PORT
# --copy-links

podman exec rclone-rcd ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
podman exec rclone-rcd mkdir -p /data/Obsidian

podman generate systemd --name rclone-rcd | tee $RCLONE_ETC_DIR/container-rclone-rcd.service

systemctl --user enable $RCLONE_ETC_DIR/container-rclone-rcd.service
systemctl --user restart container-rclone-rcd
