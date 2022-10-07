#!/bin/bash

# GEOIP_GEOSITE_ETC_DIR/update-geoip-geosite.sh

if [[ -e "/opt/podman" ]]; then
  export PATH=/opt/podman/bin:/opt/podman/libexec:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/bin/site_perl:/usr/bin/vendor_perl:/usr/bin/core_perl
else
  export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/bin/site_perl:/usr/bin/vendor_perl:/usr/bin/core_perl
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [[ "x$ROUTER_HOME" == "x" ]]; then
  source "$SCRIPT_DIR/../configure-router.sh"
fi

mkdir -p "$GEOIP_GEOSITE_ETC_DIR"
cd "$GEOIP_GEOSITE_ETC_DIR"

if [[ "x$RUN_USER" == "x" ]]; then
  RUN_USER=tools
fi

# patch for podman 1.6.3 restart BUG
#   @see https://bbs.archlinux.org/viewtopic.php?id=251410
#   @see https://github.com/containers/libpod/issues/4522

if [[ -e "all.geo.tar.gz.download" ]]; then
  rm -f all.geo.tar.gz.download
fi
curl -k -L --retry 10 --retry-max-time 1800 "https://github.com/owent/update-geoip-geosite/releases/download/latest/all.tar.gz" -o all.geo.tar.gz.download
if [[ $? -eq 0 ]]; then
  mv -f all.geo.tar.gz.download all.geo.tar.gz
  tar -axvf all.geo.tar.gz
else
  exit 1
fi

podman container inspect v2ray >/dev/null 2>&1
if [[ $? -eq 0 ]]; then

  podman cp geoip.dat v2ray:/usr/local/v2ray/bin/geoip.dat
  podman cp geosite.dat v2ray:/usr/local/v2ray/bin/geosite.dat

  systemctl disable v2ray
  systemctl stop v2ray
  systemctl enable v2ray
  systemctl start v2ray
else
  chmod +x $ROUTER_HOME/v2ray/create-v2ray-pod-with-tproxy.sh
  $ROUTER_HOME/v2ray/create-v2ray-pod-with-tproxy.sh
fi

bash "$SCRIPT_DIR/setup-geoip-geosite.sh"
