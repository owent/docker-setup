#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [[ "x$ROUTER_HOME" == "x" ]] && [[ -e "$SCRIPT_DIR/../configure-router.sh" ]]; then
  source "$SCRIPT_DIR/../configure-router.sh"
fi

podman build -t router-samba -f Dockerfile .

podman run -d --name=router-samba \
  -v $SAMBA_DATA_DIR:/data \
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
