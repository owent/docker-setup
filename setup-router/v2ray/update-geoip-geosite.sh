#!/bin/bash

# GEOIP_GEOSITE_ETC_DIR/update-geoip-geosite.sh

if [[ -e "/opt/podman" ]]; then
  export PATH=/opt/podman/bin:/opt/podman/libexec:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/bin/site_perl:/usr/bin/vendor_perl:/usr/bin/core_perl
else
  export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/bin/site_perl:/usr/bin/vendor_perl:/usr/bin/core_perl
fi

if [[ "x$ROUTER_HOME" == "x" ]]; then
  source "$(cd "$(dirname "$0")" && pwd)/../configure-router.sh"
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
  chmod +x $ROUTER_HOME/v2ray/create-v2ray-pod.sh
  $ROUTER_HOME/v2ray/create-v2ray-pod.sh
fi

if [[ -e "ipv4_cn.ipset" ]]; then
  # ipset
  ipset list GEOIP_IPV4_CN >/dev/null 2>&1
  if [[ $? -eq 0 ]]; then
    ipset flush GEOIP_IPV4_CN
  else
    ipset create GEOIP_IPV4_CN hash:net family inet
  fi

  cat ipv4_cn.ipset | ipset restore
  # nft set
  nft list table ip v2ray >/dev/null 2>&1
  if [[ $? -ne 0 ]]; then
    nft add table ip v2ray
  fi
  nft list set ip v2ray GEOIP_CN >/dev/null 2>&1
  if [[ $? -ne 0 ]]; then
    nft add set ip v2ray GEOIP_CN { type ipv4_addr\; flags interval\; }
  fi
  nft flush set ip v2ray GEOIP_CN
  # cat ipv4_cn.ipset | awk '{print $NF}' | xargs -r -I IPADDR nft add element ip v2ray GEOIP_CN { IPADDR } ;
fi

if [[ -e "ipv4_hk.ipset" ]]; then
  # ipset
  ipset list GEOIP_IPV4_HK >/dev/null 2>&1
  if [[ $? -eq 0 ]]; then
    ipset flush GEOIP_IPV4_HK
  else
    ipset create GEOIP_IPV4_HK hash:net family inet
  fi

  cat ipv4_hk.ipset | ipset restore
  # nft set
  nft list table ip v2ray >/dev/null 2>&1
  if [[ $? -ne 0 ]]; then
    nft add table ip v2ray
  fi
  nft list set ip v2ray GEOIP_HK >/dev/null 2>&1
  if [[ $? -ne 0 ]]; then
    nft add set ip v2ray GEOIP_HK { type ipv4_addr\; flags interval\; }
  fi
  nft flush set ip v2ray GEOIP_HK
  # cat ipv4_cn.ipset | awk '{print $NF}' | xargs -r -I IPADDR nft add element ip v2ray GEOIP_HK { IPADDR } ;
fi

if [[ -e "ipv6_cn.ipset" ]]; then
  # ipset
  ipset list GEOIP_IPV6_CN >/dev/null 2>&1
  if [[ $? -eq 0 ]]; then
    ipset flush GEOIP_IPV6_CN
  else
    ipset create GEOIP_IPV6_CN hash:net family inet6
  fi

  cat ipv6_cn.ipset | ipset restore
  # nft set
  nft list table ip6 v2ray >/dev/null 2>&1
  if [[ $? -ne 0 ]]; then
    nft add table ip6 v2ray
  fi
  nft list set ip6 v2ray GEOIP_CN >/dev/null 2>&1
  if [[ $? -ne 0 ]]; then
    nft add set ip6 v2ray GEOIP_CN { type ipv6_addr\; flags interval\; }
  fi
  nft flush set ip6 v2ray GEOIP_CN
  # cat ipv4_cn.ipset | awk '{print $NF}' | xargs -r -I IPADDR nft add element ip6 v2ray GEOIP_CN { IPADDR } ;
fi

if [[ -e "ipv6_hk.ipset" ]]; then
  # ipset
  ipset list GEOIP_IPV6_HK >/dev/null 2>&1
  if [[ $? -eq 0 ]]; then
    ipset flush GEOIP_IPV6_HK
  else
    ipset create GEOIP_IPV6_HK hash:net family inet6
  fi

  cat ipv6_hk.ipset | ipset restore

  # nft set
  nft list table ip6 v2ray >/dev/null 2>&1
  if [[ $? -ne 0 ]]; then
    nft add table ip6 v2ray
  fi
  nft list set ip6 v2ray GEOIP_HK >/dev/null 2>&1
  if [[ $? -ne 0 ]]; then
    nft add set ip6 v2ray GEOIP_HK { type ipv6_addr\; flags interval\; }
  fi
  nft flush set ip6 v2ray GEOIP_HK
  # cat ipv4_cn.ipset | awk '{print $NF}' | xargs -r -I IPADDR nft add element ip6 v2ray GEOIP_HK { IPADDR } ;
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
  # ipset
  # sed -i -E 's;/(1.1.1.1|8.8.8.8)#53;/127.0.0.1#6053;g' /etc/dnsmasq.d/10-dnsmasq-blacklist.router.conf # local smartdns
  IPSET_FLUSH_GFW_LIST=1
  systemctl restart dnsmasq
fi

if [[ -e "smartdns-blacklist.conf" ]] && [[ -e "$ROUTER_HOME/smartdns/merge-configure.sh" ]]; then
  bash "$ROUTER_HOME/smartdns/merge-configure.sh"
  IPSET_FLUSH_GFW_LIST=1
  systemctl restart smartdns
fi

if [[ -e "coredns-blacklist.conf" ]] && [[ -e "$ROUTER_HOME/coredns/merge-configure.sh" ]]; then
  sudo -u $RUN_USER bash "$ROUTER_HOME/coredns/merge-configure.sh"
  # IPSET_FLUSH_GFW_LIST=1
  su -c 'env DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$UID/bus systemctl restart --user coredns' - $RUN_USER
fi

if [[ $IPSET_FLUSH_GFW_LIST -ne 0 ]]; then
  bash "$ROUTER_HOME/ipset/gfw_ipv4_init.sh" DNSMASQ_GFW_IPV4
  bash "$ROUTER_HOME/ipset/gfw_ipv6_init.sh" DNSMASQ_GFW_IPV6
fi
