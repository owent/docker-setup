#!/bin/bash

if [ -e "/opt/nftables/sbin" ]; then
    export PATH=/opt/nftables/sbin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/bin/site_perl:/usr/bin/vendor_perl:/usr/bin/core_perl
else
    export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/bin/site_perl:/usr/bin/vendor_perl:/usr/bin/core_perl
fi

if [[ "x$ROUTER_HOME" == "x" ]]; then
    source "$(cd "$(dirname "$0")" && pwd)/../configure-router.sh"
fi

systemctl --all | grep -F router-nginx.service > /dev/null 2>&1 ;

if [[ $? -eq 0 ]]; then
    systemctl stop router-nginx ;
    systemctl disable router-nginx ;
fi

podman container inspect router-nginx > /dev/null 2>&1

if [[ $? -eq 0 ]]; then
    podman stop router-nginx ;
    podman rm -f router-nginx ;
fi

podman pull docker.io/nginx:latest ;

if [[ "x$NGINX_UPDATE" != "x" ]]; then
    podman image inspect docker.io/nginx:latest > /dev/null 2>&1
    if [[ $? -eq 0 ]]; then
        podman image rm -f docker.io/nginx:latest ;
    fi
fi

podman pull docker.io/nginx:latest ;

podman run -d --name router-nginx  --security-opt label=disable                                                \
       --mount type=bind,source=$ROUTER_HOME/etc/nginx/nginx.conf,target=/etc/nginx/nginx.conf,ro=true         \
       --mount type=bind,source=$ROUTER_HOME/etc/nginx/conf.d,target=/etc/nginx/conf.d,ro=true                 \
       --mount type=bind,source=$ROUTER_HOME/etc/nginx/dhparam.pem,target=/etc/nginx/dhparam.pem,ro=true       \
       --mount type=bind,source=/data/logs/nginx,target=/var/log/nginx                                         \
       --mount type=bind,source=/data/aria2/download,target=/usr/share/nginx/html/downloads                    \
       --network=host docker.io/nginx:latest nginx -c /etc/nginx/nginx.conf


podman generate systemd router-nginx | tee /lib/systemd/system/router-nginx.service

systemctl enable router-nginx
systemctl start router-nginx