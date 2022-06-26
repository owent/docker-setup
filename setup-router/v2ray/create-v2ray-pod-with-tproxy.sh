#!/bin/bash

# $ROUTER_HOME/v2ray/create-v2ray-pod.sh

if [[ -e "/opt/podman" ]]; then
  export PATH=/opt/podman/bin:/opt/podman/libexec:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/bin/site_perl:/usr/bin/vendor_perl:/usr/bin/core_perl
else
  export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/bin/site_perl:/usr/bin/vendor_perl:/usr/bin/core_perl
fi

if [[ "x$ROUTER_HOME" == "x" ]]; then
  source "$(cd "$(dirname "$0")" && pwd)/../configure-router.sh"
fi

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
  docker.io/owt5008137/proxy-with-geo:latest v2ray -config=/usr/local/v2ray/etc/config.json

podman cp v2ray:/usr/local/v2ray/share/geo-all.tar.gz geo-all.tar.gz
if [[ $? -eq 0 ]]; then
  tar -axvf geo-all.tar.gz

  if [[ $? -eq 0 ]]; then
    ipset list GEOIP_IPV4_CN >/dev/null 2>&1
    if [[ $? -eq 0 ]]; then
      ipset flush GEOIP_IPV4_CN
    else
      ipset create GEOIP_IPV4_CN hash:net family inet
    fi

    cat ipv4_cn.ipset | ipset restore

    # TODO Maybe nftable ip set
  fi

  if [[ $? -eq 0 ]]; then
    ipset list GEOIP_IPV4_HK >/dev/null 2>&1
    if [[ $? -eq 0 ]]; then
      ipset flush GEOIP_IPV4_HK
    else
      ipset create GEOIP_IPV4_HK hash:net family inet
    fi

    cat ipv4_hk.ipset | ipset restore

    # TODO Maybe nftable ip set
  fi

  if [[ $? -eq 0 ]]; then
    ipset list GEOIP_IPV6_CN >/dev/null 2>&1
    if [[ $? -eq 0 ]]; then
      ipset flush GEOIP_IPV6_CN
    else
      ipset create GEOIP_IPV6_CN hash:net family inet6
    fi

    cat ipv6_cn.ipset | ipset restore

    # TODO Maybe nftable ip set
  fi

  if [[ $? -eq 0 ]]; then
    ipset list GEOIP_IPV6_HK >/dev/null 2>&1
    if [[ $? -eq 0 ]]; then
      ipset flush GEOIP_IPV6_HK
    else
      ipset create GEOIP_IPV6_HK hash:net family inet6
    fi

    cat ipv6_hk.ipset | ipset restore

    # TODO Maybe nftable ip set
  fi

  IPSET_FLUSH_GFW_LIST=0
  if [[ -e "dnsmasq-blacklist.conf" ]] || [[ -e "dnsmasq-accelerated-cn.conf" ]] || [[ -e "dnsmasq-special-cn.conf" ]]; then
    if [[ -e "dnsmasq-blacklist.conf" ]]; then
      cp -f dnsmasq-blacklist.conf /etc/dnsmasq.d/10-dnsmasq-blacklist.router.conf
    fi
    # dnsmasq 2.86 will cost a lot CPU when server list is too large
    # if [[ -e "dnsmasq-accelerated-cn.conf" ]]; then
    #   cp -f dnsmasq-accelerated-cn.conf /etc/dnsmasq.d/11-dnsmasq-accelerated-cn.router.conf
    # fi
    # if [[ -e "dnsmasq-special-cn.conf" ]]; then
    #   cp -f dnsmasq-special-cn.conf /etc/dnsmasq.d/12-dnsmasq-special-cn.router.conf
    # fi
    IPSET_FLUSH_GFW_LIST=1
    systemctl restart dnsmasq
  fi
  if [[ -e "$ROUTER_HOME/smartdns/merge-configure.sh" ]]; then
    bash "$ROUTER_HOME/smartdns/merge-configure.sh"
    IPSET_FLUSH_GFW_LIST=1
    systemctl restart smartdns
  fi
  if [[ -e "$ROUTER_HOME/coredns/merge-configure.sh" ]]; then
    sudo -u $RUN_USER bash "$ROUTER_HOME/coredns/merge-configure.sh"
    # IPSET_FLUSH_GFW_LIST=1
    su -c 'env DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$UID/bus systemctl restart --user coredns' - $RUN_USER
  fi

  if [[ $IPSET_FLUSH_GFW_LIST -ne 0 ]]; then
    bash "$ROUTER_HOME/ipset/gfw_ipv4_init.sh" DNSMASQ_GFW_IPV4
    bash "$ROUTER_HOME/ipset/gfw_ipv6_init.sh" DNSMASQ_GFW_IPV6
  fi
fi

podman generate systemd v2ray \
  | sed "/ExecStart=/a ExecStartPost=$ROUTER_HOME/v2ray/setup-tproxy.sh" \
  | sed "/ExecStop=/a ExecStopPost=$ROUTER_HOME/v2ray/cleanup-tproxy.sh" \
  | tee /lib/systemd/system/v2ray.service

podman container stop v2ray

systemctl daemon-reload

# patch end
systemctl enable v2ray
systemctl start v2ray
