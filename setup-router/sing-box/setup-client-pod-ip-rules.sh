#!/bin/bash

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
source "$(dirname "$SCRIPT_DIR")/configure-router.sh"

if [[ -z "$VBOX_ETC_DIR" ]]; then
  VBOX_ETC_DIR="$HOME/vbox/etc"
fi

if [[ -z "$VBOX_DATA_DIR" ]]; then
  VBOX_DATA_DIR="$HOME/vbox/data"
fi

if [[ -z "$ROUTER_IP_RULE_GOTO_DEFAULT_PRIORITY" ]]; then
  ROUTER_IP_RULE_GOTO_DEFAULT_PRIORITY=20901
fi
if [[ -z "$VBOX_SKIP_IP_RULE_PRIORITY" ]]; then
  VBOX_SKIP_IP_RULE_PRIORITY=8123
fi

if [[ "x$1" != "xclear" ]]; then
  VBOX_SETUP_IP_RULE_CLEAR=0
else
  VBOX_SETUP_IP_RULE_CLEAR=1
fi

function vbox_setup_patch_configures() {
  PATCH_CONF_FILES=($(find "$VBOX_ETC_DIR" -maxdepth 1 -name "*.json.template"))
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
  PATCH_CONF_FILES=($(find "$VBOX_ETC_DIR" -maxdepth 1 -name "*.json.template"))
  if [ ${#PATCH_CONF_FILES[@]} -eq 0 ]; then
    return 0
  fi

  for PATCH_CONF_FILE in "${PATCH_CONF_FILES[@]}"; do
    TARGET_CONF_FILE_BASENAME="$(basename "$PATCH_CONF_FILE" | sed -E 's;.template$;;')"
    cp -f "$PATCH_CONF_FILE" "$VBOX_ETC_DIR/$TARGET_CONF_FILE_BASENAME"
  done
}

if [ $VBOX_SETUP_IP_RULE_CLEAR -eq 0 ]; then
  vbox_setup_patch_configures
else
  vbox_cleanup_patch_configures
fi
