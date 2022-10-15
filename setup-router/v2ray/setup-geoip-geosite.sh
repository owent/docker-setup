#!/bin/bash

# GEOIP_GEOSITE_ETC_DIR/update-geoip-geosite.sh

if [[ -e "/opt/podman" ]]; then
  export PATH=/opt/podman/bin:/opt/podman/libexec:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/bin/site_perl:/usr/bin/vendor_perl:/usr/bin/core_perl
else
  export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/bin/site_perl:/usr/bin/vendor_perl:/usr/bin/core_perl
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../configure-router.sh"

function update_geo_services() {
  if [ $TPROXY_SETUP_IPSET -ne 0 ]; then
    if [ $TPROXY_SETUP_USING_GEOIP -ne 0 ]; then
      # ipv4 - cn
      ipset list GEOIP_IPV4_CN >/dev/null 2>&1
      if [ $? -eq 0 ]; then
        ipset flush GEOIP_IPV4_CN
      else
        ipset create GEOIP_IPV4_CN hash:net family inet
      fi
      cat ipv4_cn.ipset | ipset restore

      # ipv4 - hk
      ipset list GEOIP_IPV4_HK >/dev/null 2>&1
      if [ $? -eq 0 ]; then
        ipset flush GEOIP_IPV4_HK
      else
        ipset create GEOIP_IPV4_HK hash:net family inet
      fi
      cat ipv4_hk.ipset | ipset restore

      if [ $TPROXY_SETUP_WITHOUT_IPV6 -eq 0 ]; then
        # ipv6 - cn
        ipset list GEOIP_IPV6_CN >/dev/null 2>&1
        if [ $? -eq 0 ]; then
          ipset flush GEOIP_IPV6_CN
        else
          ipset create GEOIP_IPV6_CN hash:net family inet6
        fi
        cat ipv6_cn.ipset | ipset restore

        # ipv6 - hk
        ipset list GEOIP_IPV6_HK >/dev/null 2>&1
        if [ $? -eq 0 ]; then
          ipset flush GEOIP_IPV6_HK
        else
          ipset create GEOIP_IPV6_HK hash:net family inet6
        fi
        cat ipv6_hk.ipset | ipset restore
      fi
    fi
  fi

  if [ $TPROXY_SETUP_NFTABLES -ne 0 ]; then
    nft list table ip v2ray >/dev/null 2>&1
    if [[ $? -ne 0 ]]; then
      nft add table ip v2ray
    fi
    nft list table bridge v2ray >/dev/null 2>&1
    if [[ $? -ne 0 ]]; then
      nft add table bridge v2ray
    fi

    nft list set ip v2ray PERMANENT_WHITELIST >/dev/null 2>&1
    if [ $? -ne 0 ]; then
      nft add set ip v2ray PERMANENT_WHITELIST '{ type ipv4_addr; flags interval; auto-merge; }'
    else
      nft flush set ip v2ray PERMANENT_WHITELIST
    fi
    nft add element ip v2ray PERMANENT_WHITELIST "{$(echo "${TPROXY_WHITELIST_IPV4[@]}" | sed -E 's;[[:space:]]+;,;g')}"

    nft list set bridge v2ray PERMANENT_WHITELIST_IPV4 >/dev/null 2>&1
    if [[ $? -ne 0 ]]; then
      nft add set bridge v2ray PERMANENT_WHITELIST_IPV4 '{ type ipv4_addr; flags interval; auto-merge; }'
    else
      nft flush set bridge v2ray PERMANENT_WHITELIST_IPV4
    fi
    nft add element bridge v2ray PERMANENT_WHITELIST_IPV4 "{$(echo "${TPROXY_WHITELIST_IPV4[@]}" | sed -E 's;[[:space:]]+;,;g')}"

    # ipv4 - cn
    if [ $TPROXY_SETUP_USING_GEOIP -ne 0 ]; then
      nft list set ip v2ray GEOIP_CN >/dev/null 2>&1
      if [ $? -ne 0 ]; then
        nft add set ip v2ray GEOIP_CN '{ type ipv4_addr; flags interval; }'
      else
        nft flush set ip v2ray GEOIP_CN
      fi
      cat ipv4_cn.ipset | awk '{print "add element ip v2ray GEOIP_CN {"$NF"}"}' | nft -f -

      nft list set bridge v2ray GEOIP_CN_IPV4 >/dev/null 2>&1
      if [ $? -ne 0 ]; then
        nft add set bridge v2ray GEOIP_CN_IPV4 '{ type ipv4_addr; flags interval; }'
      else
        nft flush set bridge v2ray GEOIP_CN_IPV4
      fi
      cat ipv4_cn.ipset | awk '{print "add element bridge v2ray GEOIP_CN_IPV4 {"$NF"}"}' | nft -f -
    fi

    if [ $TPROXY_SETUP_WITHOUT_IPV6 -eq 0 ]; then
      nft list table ip6 v2ray >/dev/null 2>&1
      if [[ $? -ne 0 ]]; then
        nft add table ip6 v2ray
      fi

      nft list set ip6 v2ray PERMANENT_WHITELIST >/dev/null 2>&1
      if [ $? -ne 0 ]; then
        nft add set ip6 v2ray PERMANENT_WHITELIST '{ type ipv6_addr; flags interval; auto-merge; }'
      else
        nft flush set ip6 v2ray PERMANENT_WHITELIST
      fi
      nft add element ip6 v2ray PERMANENT_WHITELIST "{$(echo "${SETUP_WITH_WHITELIST_IPV6[@]}" | sed -E 's;[[:space:]]+;,;g')}"

      nft list set bridge v2ray PERMANENT_WHITELIST_IPV6 >/dev/null 2>&1
      if [[ $? -ne 0 ]]; then
        nft add set bridge v2ray PERMANENT_WHITELIST_IPV6 '{ type ipv6_addr; flags interval; auto-merge; }'
      else
        nft flush set bridge v2ray PERMANENT_WHITELIST_IPV6
      fi
      nft add element bridge v2ray PERMANENT_WHITELIST_IPV6 "{$(echo "${SETUP_WITH_WHITELIST_IPV6[@]}" | sed -E 's;[[:space:]]+;,;g')}"

      if [ $TPROXY_SETUP_USING_GEOIP -ne 0 ]; then
        # ipv6 - cn
        nft list set ip6 v2ray GEOIP_CN >/dev/null 2>&1
        if [ $? -ne 0 ]; then
          nft add set ip6 v2ray GEOIP_CN '{ type ipv6_addr; flags interval; }'
        else
          nft flush set ip6 v2ray GEOIP_CN
        fi
        cat ipv6_cn.ipset | awk '{print "add element ip6 v2ray GEOIP_CN {"$NF"}"}' | nft -f -

        nft list set bridge v2ray GEOIP_CN_IPV6 >/dev/null 2>&1
        if [ $? -ne 0 ]; then
          nft add set bridge v2ray GEOIP_CN_IPV6 '{ type ipv6_addr; flags interval; }'
        else
          nft flush set bridge v2ray GEOIP_CN_IPV6
        fi
        cat ipv6_cn.ipset | awk '{print "add element bridge v2ray GEOIP_CN_IPV6 {"$NF"}"}' | nft -f -
      fi
    fi
  fi

  IPSET_FLUSH_GFW_LIST=0
  if [ -e "dnsmasq-blacklist.conf" ] && [ $TPROXY_SETUP_DNSMASQ -ne 0 ]; then
    if [ -e "dnsmasq-blacklist.conf" ]; then
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

  if [ -e "$ROUTER_HOME/smartdns/merge-configure.sh" ] && [ $TPROXY_SETUP_SMARTDNS -ne 0 ]; then
    bash "$ROUTER_HOME/smartdns/merge-configure.sh"
    IPSET_FLUSH_GFW_LIST=1
    systemctl restart smartdns
  fi

  if [ -e "$ROUTER_HOME/coredns/merge-configure.sh" ] && [ $TPROXY_SETUP_COREDNS -ne 0 ]; then
    if [ $TPROXY_SETUP_COREDNS_WITH_NFTABLES -ne 0 ]; then
      sudo bash "$ROUTER_HOME/coredns/merge-configure.sh"
      sudo systemctl restart coredns
    else
      sudo -u $RUN_USER bash "$ROUTER_HOME/coredns/merge-configure.sh"
      su -c 'env DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$UID/bus systemctl restart --user coredns' - $RUN_USER
    fi
  fi

  if [ $IPSET_FLUSH_GFW_LIST -ne 0 ] && [ $TPROXY_SETUP_IPSET -ne 0 ]; then
    ipset list DNSMASQ_GFW_IPV4 >/dev/null 2>&1
    if [[ $? -eq 0 ]]; then
      ipset flush DNSMASQ_GFW_IPV4
    else
      ipset create DNSMASQ_GFW_IPV4 hash:ip family inet
    fi
    for TPROXY_WHITELIST_IPV4_ADDR in ${TPROXY_WHITELIST_IPV4[@]}; do
      ipset add DNSMASQ_GFW_IPV4 "$TPROXY_WHITELIST_IPV4_ADDR"
    done

    ipset list DNSMASQ_GFW_IPV6 >/dev/null 2>&1
    if [[ $? -eq 0 ]]; then
      ipset flush DNSMASQ_GFW_IPV6
    else
      ipset create DNSMASQ_GFW_IPV6 hash:ip family inet6
    fi
    for TPROXY_WHITELIST_IPV6_ADDR in ${TPROXY_WHITELIST_IPV6[@]}; do
      ipset add DNSMASQ_GFW_IPV6 "$TPROXY_WHITELIST_IPV6_ADDR"
    done
  fi
}

if [ ! -e "ipv4_cn.ipset" ]; then
  cd "$GEOIP_GEOSITE_ETC_DIR"
fi

if [ -e "ipv4_cn.ipset" ]; then
  update_geo_services
fi
