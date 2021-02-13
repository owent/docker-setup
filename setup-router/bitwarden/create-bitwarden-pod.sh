#!/bin/bash

if [ -e "/opt/nftables/sbin" ]; then
    export PATH=/opt/nftables/sbin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/bin/site_perl:/usr/bin/vendor_perl:/usr/bin/core_perl
else
    export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/bin/site_perl:/usr/bin/vendor_perl:/usr/bin/core_perl
fi

export XDG_RUNTIME_DIR="/run/user/$UID"
export DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR}/bus"

if [[ "x$(whoami)" == "x" ]] || [[ "x$(whoami)" == "xroot" ]]; then
    echo -e "\033[1;32m$0 can not run with\033[0;m \033[1;31m$(whoami)\033[0;m" ;
    exit 1;
fi

# sudo loginctl enable-linger tools

systemctl --user --all | grep -F container-bitwarden.service ;

if [[ $? -eq 0 ]]; then
    systemctl --user stop container-bitwarden ;
    systemctl --user disable container-bitwarden ;
fi

podman container inspect bitwarden > /dev/null 2>&1

if [[ $? -eq 0 ]]; then
    podman stop bitwarden ;
    podman rm -f bitwarden ;
fi

if [[ "x$BITWARDEN_UPDATE" != "x" ]]; then
    podman image inspect docker.io/bitwardenrs/server:latest > /dev/null 2>&1
    if [[ $? -eq 0 ]]; then
        podman image rm -f docker.io/bitwardenrs/server:latest ;
    fi
fi

podman pull docker.io/bitwardenrs/server:latest ;

ADMIN_TOKEN=$(openssl rand -base64 48);

# -e SMTP_HOST=smtp.exmail.qq.com                                                   \
# -e SMTP_FROM=admin@owent.net                                                      \
# -e SMTP_PORT=465                                                                  \
# -e SMTP_SSL=true                                                                  \
# -e SMTP_USERNAME=admin@owent.net                                                  \
# -e SMTP_PASSWORD=<TOKEN>                                                          \

# -e ROCKET_WORKERS=8

podman run -d --name bitwarden                                                           \
       -e ROCKET_TLS='{certs="/ssl/fullchain.cer",key="/ssl/owent.net.key"}'             \
       -e DOMAIN=https://bitwarden.x-ha.com:8381/                                        \
       -e SIGNUPS_ALLOWED=false -e WEBSOCKET_ENABLED=true                                \
       -e ROCKET_PORT=8381 -e WEBSOCKET_PORT=8382                                        \
       -e INVITATIONS_ALLOWED=false -e LOG_FILE=/logs/bitwarden.log                      \
       -e ADMIN_TOKEN=$ADMIN_TOKEN                                                       \
       --mount type=bind,source=/data/logs/bitwarden/,target=/logs/                      \
       -v /home/router/bitwarden/data/:/data/:Z                                          \
       --mount type=bind,source=/home/router/bitwarden/ssl/,target=/ssl/                 \
       --network=host docker.io/bitwardenrs/server:latest

echo $ADMIN_TOKEN > /home/router/bitwarden/ADMIN_TOKEN ;

chmod 700 /home/router/bitwarden/ADMIN_TOKEN ;

podman generate systemd --name bitwarden | tee /home/router/bitwarden/container-bitwarden.service ;

systemctl --user enable /home/router/bitwarden/container-bitwarden.service ;
systemctl --user start container-bitwarden

