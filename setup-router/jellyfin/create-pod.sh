#!/bin/bash

# @see https://hub.docker.com/r/jellyfin/jellyfin
# https://jellyfin.org/docs/general/administration/hardware-acceleration.html

systemctl disable jellyfin ;
systemctl stop jellyfin ;

podman container inspect jellyfin > /dev/null 2>&1
if [[ $? -eq 0 ]]; then
    podman stop jellyfin
    podman rm -f jellyfin
fi

if [[ "x$JELLYFIN_UPDATE" != "x" ]]; then
    podman image inspect docker.io/jellyfin/jellyfin:latest > /dev/null 2>&1
    if [[ $? -eq 0 ]]; then
        podman image rm -f docker.io/jellyfin/jellyfin:latest ;
    fi
fi

#    --device /dev/dri:/dev/dri                         \

podman run --network=host --name jellyfin -d         \
    -v /home/router/etc/jellyfin:/config             \
    -v /home/router/jellyfin/cache:/cache            \
    -v /data/samba:/media/samba                      \
    -v /data/aria2/download:/media/download          \
    --device /dev/dri/renderD128:/dev/dri/renderD128 \
    --device /dev/dri/card0:/dev/dri/card0           \
    --publish 8096:8096                              \
    docker.io/jellyfin/jellyfin:latest

if [ 0 -ne $? ]; then
    exit $? ;
fi

podman generate systemd jellyfin | tee /lib/systemd/system/jellyfin.service

systemctl daemon-reload ;

# patch end
systemctl enable jellyfin ;
systemctl start jellyfin ;