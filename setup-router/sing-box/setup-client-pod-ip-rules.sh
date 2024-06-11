#!/bin/bash

# $ROUTER_HOME/sing-box/create-client-pod.sh
# nftables
# Quick: https://wiki.nftables.org/wiki-nftables/index.php/Performing_Network_Address_Translation_(NAT)
# Quick(CN): https://wiki.archlinux.org/index.php/Nftables_(%E7%AE%80%E4%BD%93%E4%B8%AD%E6%96%87)#Masquerading
# List all tables/chains/rules/matches/statements: https://wiki.nftables.org/wiki-nftables/index.php/Quick_reference-nftables_in_10_minutes#Rules
# man 8 nft:
#    https://www.netfilter.org/projects/nftables/manpage.html
#    https://www.mankier.com/8/nft
# IP http://ftp.apnic.net/apnic/stats/apnic/delegated-apnic-latest
#    ipv4 <start> <count> => ipv4 58.42.0.0 65536
#    ipv6 <prefix> <bits> => ipv6 2407:c380:: 32
# Netfilter: https://en.wikipedia.org/wiki/Netfilter
#            http://inai.de/images/nf-packet-flow.svg
# Policy Routing: See RPDB in https://www.man7.org/linux/man-pages/man8/ip-rule.8.html
# Monitor: nft monitor

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
source "$(dirname "$SCRIPT_DIR")/configure-router.sh"

if [[ -z "$VBOX_ETC_DIR" ]]; then
  VBOX_ETC_DIR="$HOME/vbox/etc"
fi

if [[ -z "$VBOX_DATA_DIR" ]]; then
  VBOX_DATA_DIR="$HOME/vbox/data"
fi

### 策略路由(占用mark的后4位,RPDB变化均会触发重路由, meta mark and 0x0f != 0x0 都跳过重路由):
###   不需要重路由设置: meta mark and 0x0f != 0x0
###   走 tun: 设置 fwmark = 0x03/0x03 (0011)
###   直接跳转到默认路由: 跳过 fwmark = 0x0c/0x0c (1100)
###     (vbox会设置511,0x1ff), 避开 meta mark and 0x0f != 0x0 规则 (防止循环重定向)

if [[ -z "$ROUTER_IP_RULE_GOTO_DEFAULT_PRIORITY" ]]; then
  ROUTER_IP_RULE_GOTO_DEFAULT_PRIORITY=20901
fi
if [[ -z "$VBOX_SKIP_IP_RULE_PRIORITY" ]]; then
  VBOX_SKIP_IP_RULE_PRIORITY=8123
fi

if [[ "x$1" != "xclear" ]]; then
  VBOX_SETUP_IP_RULE_CLEAR=1
else
  VBOX_SETUP_IP_RULE_CLEAR=0
fi

function vbox_setup_patch_configures() {
  PATCH_CONF_FILES=($(find "$VBOX_ETC_DIR" -name "*.json.template"))
  if [ ${#PATCH_CONF_FILES[@]} -eq 0 ]; then
    return 0
  fi

  if [[ -e "$VBOX_DATA_DIR/geoip-cn.json" ]] && [[ -e "$VBOX_DATA_DIR/geoip-cn.json.bak" ]]; then
    rm -f "$VBOX_DATA_DIR/geoip-cn.json.bak"
  fi

  if [[ -e "$VBOX_DATA_DIR/geoip-cn.json" ]]; then
    mv -f "$VBOX_DATA_DIR/geoip-cn.json" "$VBOX_DATA_DIR/geoip-cn.json.bak"
  fi

  podman exec -it vbox-client vbox geoip export cn -f /usr/share/vbox/geoip.db -o /usr/share/vbox/geoip-cn.json
  podman cp vbox-client:/usr/share/vbox/geoip-cn.json "$VBOX_DATA_DIR/geoip-cn.json" || mv -f "$VBOX_DATA_DIR/geoip-cn.json.bak" "$VBOX_DATA_DIR/geoip-cn.json"

  GEOIP_CN_ADDRESS_IPV4=($(jq '.rules[].ip_cidr[]' -r "$VBOX_DATA_DIR/geoip-cn.json" | grep -v ':'))
  GEOIP_CN_ADDRESS_IPV6=($(jq '.rules[].ip_cidr[]' -r "$VBOX_DATA_DIR/geoip-cn.json" | grep ':'))

  if [[ -e "$SCRIPT_DIR/patch" ]]; then
    rm -rf "$SCRIPT_DIR/patch"
  fi
  mkdir -p "$SCRIPT_DIR/patch"

  for PATCH_CONF_FILE in "${PATCH_CONF_FILES[@]}"; do
    TARGET_CONF_FILE="$SCRIPT_DIR/patch/$(basename "$PATCH_CONF_FILE" | sed -E 's;.template$;;')"
    IPV4_PLACEHOLDER=$(grep -nr INET4_ROUTE_EXLUCDE_ADDRESS_PLACEHOLDER "$PATCH_CONF_FILE" | awk 'BEGIN{FS=":"}{print $1}')
    IPV6_PLACEHOLDER=$(grep -nr INET6_ROUTE_EXLUCDE_ADDRESS_PLACEHOLDER "$PATCH_CONF_FILE" | awk 'BEGIN{FS=":"}{print $1}')

    if [[ -z "$IPV4_PLACEHOLDER" ]] && [[ -z "$IPV6_PLACEHOLDER" ]]; then
      echo "No placeholder found in $PATCH_CONF_FILE"
      continue
    fi

    if [[ -z "$IPV6_PLACEHOLDER" ]]; then
      sed -n "1,$((IPV4_PLACEHOLDER - 1))p" "$PATCH_CONF_FILE" >"$TARGET_CONF_FILE"
      for IP_CIDR in "${GEOIP_CN_ADDRESS_IPV4[@]}"; do
        echo "        ,\"$IP_CIDR\"" >>"$TARGET_CONF_FILE"
      done
      echo "        // INET4_ROUTE_EXLUCDE_ADDRESS_PATCHED" >>"$TARGET_CONF_FILE"
      sed -n "$((IPV4_PLACEHOLDER + 1)),$ p" "$PATCH_CONF_FILE" >>"$TARGET_CONF_FILE"
    elif [[ -z "$IPV4_PLACEHOLDER" ]]; then
      sed -n "1,$((IPV6_PLACEHOLDER - 1))p" "$PATCH_CONF_FILE" >"$TARGET_CONF_FILE"
      for IP_CIDR in "${GEOIP_CN_ADDRESS_IPV6[@]}"; do
        echo "        ,\"$IP_CIDR\"" >>"$TARGET_CONF_FILE"
      done
      echo "        // INET6_ROUTE_EXLUCDE_ADDRESS_PATCHED" >>"$TARGET_CONF_FILE"
      sed -n "$((IPV6_PLACEHOLDER + 1)),$ p" "$PATCH_CONF_FILE" >>"$TARGET_CONF_FILE"
    elif [ $IPV4_PLACEHOLDER -lt $IPV6_PLACEHOLDER ]; then
      sed -n "1,$((IPV4_PLACEHOLDER - 1))p" "$PATCH_CONF_FILE" >"$TARGET_CONF_FILE"
      for IP_CIDR in "${GEOIP_CN_ADDRESS_IPV4[@]}"; do
        echo "        ,\"$IP_CIDR\"" >>"$TARGET_CONF_FILE"
      done
      echo "        // INET4_ROUTE_EXLUCDE_ADDRESS_PATCHED" >>"$TARGET_CONF_FILE"

      sed -n "$((IPV4_PLACEHOLDER + 1)),$((IPV6_PLACEHOLDER - 1))p" "$PATCH_CONF_FILE" >>"$TARGET_CONF_FILE"
      for IP_CIDR in "${GEOIP_CN_ADDRESS_IPV6[@]}"; do
        echo "        ,\"$IP_CIDR\"" >>"$TARGET_CONF_FILE"
      done
      echo "        // INET6_ROUTE_EXLUCDE_ADDRESS_PATCHED" >>"$TARGET_CONF_FILE"
      sed -n "$((IPV6_PLACEHOLDER + 1)),$ p" "$PATCH_CONF_FILE" >>"$TARGET_CONF_FILE"
    else
      sed -n "1,$((IPV6_PLACEHOLDER - 1))p" "$PATCH_CONF_FILE" >"$TARGET_CONF_FILE"
      for IP_CIDR in "${GEOIP_CN_ADDRESS_IPV6[@]}"; do
        echo "        ,\"$IP_CIDR\"" >>"$TARGET_CONF_FILE"
      done
      echo "        // INET6_ROUTE_EXLUCDE_ADDRESS_PATCHED" >>"$TARGET_CONF_FILE"

      sed -n "$((IPV6_PLACEHOLDER + 1)),$((IPV4_PLACEHOLDER - 1))p" "$PATCH_CONF_FILE" >>"$TARGET_CONF_FILE"
      for IP_CIDR in "${GEOIP_CN_ADDRESS_IPV4[@]}"; do
        echo "        ,\"$IP_CIDR\"" >>"$TARGET_CONF_FILE"
      done
      echo "        // INET4_ROUTE_EXLUCDE_ADDRESS_PATCHED" >>"$TARGET_CONF_FILE"
      sed -n "$((IPV4_PLACEHOLDER + 1)),$ p" "$PATCH_CONF_FILE" >>"$TARGET_CONF_FILE"
    fi

    echo "Copy patched configure file: $TARGET_CONF_FILE to $VBOX_ETC_DIR/"
    cp -f "$TARGET_CONF_FILE" "$VBOX_ETC_DIR/"
  done
}

function vbox_cleanup_patch_configures() {
  PATCH_CONF_FILES=($(find "$VBOX_ETC_DIR" -name "*.json.template"))
  if [ ${#PATCH_CONF_FILES[@]} -eq 0 ]; then
    return 0
  fi

  # cp -f "${PATCH_CONF_FILES[@]}" "$VBOX_ETC_DIR/"
}

if [ $VBOX_SETUP_IP_RULE_CLEAR -ne 0 ]; then
  vbox_setup_patch_configures
else
  vbox_cleanup_patch_configures
fi
