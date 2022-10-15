#!/bin/bash

# $ROUTER_HOME/v2ray/create-v2ray-pod.sh

if [[ -e "/opt/podman" ]]; then
  export PATH=/opt/podman/bin:/opt/podman/libexec:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/bin/site_perl:/usr/bin/vendor_perl:/usr/bin/core_perl
else
  export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/bin/site_perl:/usr/bin/vendor_perl:/usr/bin/core_perl
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../configure-router.sh"

mkdir -p "$ROUTER_LOG_ROOT_DIR/v2ray"
mkdir -p "$GEOIP_GEOSITE_ETC_DIR"
cd "$GEOIP_GEOSITE_ETC_DIR"

if [[ "x$V2RAY_UPDATE" != "x" ]] || [[ "x$ROUTER_IMAGE_UPDATE" != "x" ]]; then
  podman pull docker.io/owt5008137/proxy-with-geo:latest
fi

systemctl disable v2ray
systemctl stop v2ray

podman container inspect v2ray >/dev/null 2>&1
if [[ $? -eq 0 ]]; then
  podman stop v2ray
  podman rm -f v2ray
fi

if [[ "x$V2RAY_UPDATE" != "x" ]] || [[ "x$ROUTER_IMAGE_UPDATE" != "x" ]]; then
  podman image prune -a -f --filter "until=240h"
fi

podman run -d --name v2ray --cap-add=NET_ADMIN --network=host --security-opt label=disable \
  --mount type=bind,source=$GEOIP_GEOSITE_ETC_DIR,target=/usr/local/v2ray/etc,ro=true \
  --mount type=bind,source=$ROUTER_LOG_ROOT_DIR/v2ray,target=/data/logs/v2ray \
  --mount type=bind,source=$ACMESH_SSL_DIR,target=/usr/local/v2ray/ssl,ro=true \
  docker.io/owt5008137/proxy-with-geo:latest v2ray run -c /usr/local/v2ray/etc/config.json

podman cp v2ray:/usr/local/v2ray/share/geo-all.tar.gz geo-all.tar.gz
if [[ $? -eq 0 ]]; then
  tar -axvf geo-all.tar.gz
  if [ $? -eq 0 ]; then
    bash "$SCRIPT_DIR/setup-geoip-geosite.sh"
  fi
fi

if [ $TPROXY_SETUP_NFTABLES -eq 0 ]; then
  podman generate systemd v2ray \
    | sed "/ExecStart=/a ExecStartPost=$ROUTER_HOME/v2ray/setup-tproxy.sh" \
    | sed "/ExecStop=/a ExecStopPost=$ROUTER_HOME/v2ray/cleanup-tproxy.sh" \
    | tee /lib/systemd/system/v2ray.service
else
  podman generate systemd v2ray \
    | sed "/ExecStart=/a ExecStartPost=$ROUTER_HOME/v2ray/setup-tproxy.nft.sh" \
    | sed "/ExecStop=/a ExecStopPost=$ROUTER_HOME/v2ray/cleanup-tproxy.nft.sh" \
    | tee /lib/systemd/system/v2ray.service
fi

podman container stop v2ray

systemctl daemon-reload

# patch end
systemctl enable v2ray
systemctl start v2ray
