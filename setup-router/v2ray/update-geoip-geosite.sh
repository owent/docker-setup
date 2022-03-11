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

podman container inspect v2ray >/dev/null 2>&1
if [[ $? -eq 0 ]]; then

  if [[ -e "geoip.dat" ]]; then
    rm -f "geoip.dat"
  fi
  curl -k -L --retry 10 --retry-max-time 1800 "https://github.com/owent/update-geoip-geosite/releases/download/latest/geoip.dat" -o geoip.dat
  if [[ $? -eq 0 ]]; then
    podman cp geoip.dat v2ray:/usr/local/v2ray/bin/geoip.dat
  fi

  if [[ -e "geosite.dat" ]]; then
    rm -f "geosite.dat"
  fi
  curl -k -L --retry 10 --retry-max-time 1800 "https://github.com/owent/update-geoip-geosite/releases/download/latest/geosite.dat" -o geosite.dat
  if [[ $? -eq 0 ]]; then
    podman cp geosite.dat v2ray:/usr/local/v2ray/bin/geosite.dat
  fi

  systemctl disable v2ray
  systemctl stop v2ray
  systemctl enable v2ray
  systemctl start v2ray
else
  chmod +x $ROUTER_HOME/v2ray/create-v2ray-pod.sh
  $ROUTER_HOME/v2ray/create-v2ray-pod.sh
fi

curl -k -L --retry 10 --retry-max-time 1800 "https://github.com/owent/update-geoip-geosite/releases/download/latest/ipv4_cn.ipset" -o ipv4_cn.ipset
if [[ $? -eq 0 ]]; then
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

curl -k -L --retry 10 --retry-max-time 1800 "https://github.com/owent/update-geoip-geosite/releases/download/latest/ipv4_hk.ipset" -o ipv4_hk.ipset
if [[ $? -eq 0 ]]; then
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

curl -k -L --retry 10 --retry-max-time 1800 "https://github.com/owent/update-geoip-geosite/releases/download/latest/ipv6_cn.ipset" -o ipv6_cn.ipset
if [[ $? -eq 0 ]]; then
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

curl -k -L --retry 10 --retry-max-time 1800 "https://github.com/owent/update-geoip-geosite/releases/download/latest/ipv6_hk.ipset" -o ipv6_hk.ipset
if [[ $? -eq 0 ]]; then
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
curl -k -L --retry 10 --retry-max-time 1800 "https://github.com/owent/update-geoip-geosite/releases/download/latest/dnsmasq-blacklist.conf" -o dnsmasq-blacklist.conf
if [[ $? -eq 0 ]]; then
  # ipset
  cp -f dnsmasq-blacklist.conf /etc/dnsmasq.d/10-dnsmasq-blacklist.router.conf
  # sed -i -E 's;/(1.1.1.1|8.8.8.8)#53;/127.0.0.1#6053;g' /etc/dnsmasq.d/10-dnsmasq-blacklist.router.conf # local smartdns
  IPSET_FLUSH_GFW_LIST=1
  systemctl restart dnsmasq
fi

curl -k -L --retry 10 --retry-max-time 1800 "https://github.com/owent/update-geoip-geosite/releases/download/latest/smartdns-blacklist.conf" -o smartdns-blacklist.conf
if [[ $? -eq 0 ]] && [[ -e "$ROUTER_HOME/smartdns/merge-configure.sh" ]]; then
  bash "$ROUTER_HOME/smartdns/merge-configure.sh"
  IPSET_FLUSH_GFW_LIST=1
  su -c 'env DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$UID/bus systemctl restart --user smartdns' - $RUN_USER
fi

if [[ $IPSET_FLUSH_GFW_LIST -ne 0 ]]; then
  ipset list DNSMASQ_GFW_IPV4 >/dev/null 2>&1
  if [ $? -eq 0 ]; then
    ipset flush DNSMASQ_GFW_IPV4
  else
    ipset create DNSMASQ_GFW_IPV4 hash:ip family inet
  fi

  ipset list DNSMASQ_GFW_IPV6 >/dev/null 2>&1
  if [[ $? -eq 0 ]]; then
    ipset flush DNSMASQ_GFW_IPV6
  else
    ipset create DNSMASQ_GFW_IPV6 hash:ip family inet6
  fi
fi
