#!/bin/bash

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
source "$(dirname "$SCRIPT_DIR")/configure-router.sh"

DOCKER_EXEC=$((which podman > /dev/null 2>&1 && echo podman) || (which docker > /dev/null 2>&1 && echo docker))

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

if [[ -z "$VBOX_IP_RULE_WITH_AUTO_REDIRECT" ]]; then
  VBOX_IP_RULE_WITH_AUTO_REDIRECT=0
fi

if [[ "x$1" != "xclear" ]]; then
  VBOX_SETUP_IP_RULE_CLEAR=0
else
  VBOX_SETUP_IP_RULE_CLEAR=1
fi

function vbox_setup_patch_configures_without_auto_redirect() {
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

  $DOCKER_EXEC exec -it vbox-client vbox geoip export cn -f /usr/share/vbox/geoip.db -o /usr/share/vbox/geoip-cn.json
  $DOCKER_EXEC cp vbox-client:/usr/share/vbox/geoip-cn.json "$VBOX_DATA_DIR/geoip-cn.json" || mv -f "$VBOX_DATA_DIR/geoip-cn.json.bak" "$VBOX_DATA_DIR/geoip-cn.json"

  # tun排除规则性能非常差，尽量还是走 ip-nft 模式自己来吧
  GEOIP_CN_ADDRESS=($(jq '.rules[].ip_cidr[]' -r "$VBOX_DATA_DIR/geoip-cn.json"))

  if [[ -e "$SCRIPT_DIR/patch" ]]; then
    rm -rf "$SCRIPT_DIR/patch"
  fi
  mkdir -p "$SCRIPT_DIR/patch"

  for PATCH_CONF_FILE in "${PATCH_CONF_FILES[@]}"; do
    TARGET_CONF_FILE="$SCRIPT_DIR/patch/$(basename "$PATCH_CONF_FILE" | sed -E 's;.template$;;')"
    # tun排除规则性能非常差，尽量还是走 ip-nft 模式自己来吧
    GEOIP_ADDRESS_PLACEHOLDER=$(grep -nr ROUTE_EXLUCDE_ADDRESS_PLACEHOLDER "$PATCH_CONF_FILE" | awk 'BEGIN{FS=":"}{print $1}')
    
    if [[ -z "$GEOIP_ADDRESS_PLACEHOLDER" ]]; then
      echo "No placeholder found in $PATCH_CONF_FILE"
      continue
    fi
    
    sed -n "1,$((GEOIP_ADDRESS_PLACEHOLDER - 1))p" "$PATCH_CONF_FILE" >"$TARGET_CONF_FILE"
    for IP_CIDR in "${GEOIP_CN_ADDRESS[@]}"; do
      echo "        ,\"$IP_CIDR\"" >>"$TARGET_CONF_FILE"
    done
    echo "        // ROUTE_EXLUCDE_ADDRESS_PATCHED" >>"$TARGET_CONF_FILE"
    sed -n "$((GEOIP_ADDRESS_PLACEHOLDER + 1)),$ p" "$PATCH_CONF_FILE" >>"$TARGET_CONF_FILE"

    sed -i -E 's;(//[[:space:]]*)?"auto_redirect":[^,]+,;"auto_redirect": false,;g' "$TARGET_CONF_FILE"
    sed -i -E 's;(//[[:space:]]*)?"default_mark":([^,]+),;"default_mark":\2,;g' "$TARGET_CONF_FILE"
    sed -i -E 's;(//[[:space:]]*)?"routing_mark":([^,]+),;"routing_mark":\2,;g' "$TARGET_CONF_FILE"

    echo "Copy patched configure file: $TARGET_CONF_FILE to $VBOX_ETC_DIR/"
    cp -f "$TARGET_CONF_FILE" "$VBOX_ETC_DIR/"
  done
}

function vbox_setup_patch_configures_with_auto_redirect() {
  PATCH_CONF_FILES=($(find "$VBOX_ETC_DIR" -maxdepth 1 -name "*.json.template"))
  if [ ${#PATCH_CONF_FILES[@]} -eq 0 ]; then
    return 0
  fi

  if [[ -e "$SCRIPT_DIR/patch" ]]; then
    rm -rf "$SCRIPT_DIR/patch"
  fi
  mkdir -p "$SCRIPT_DIR/patch"

  for PATCH_CONF_FILE in "${PATCH_CONF_FILES[@]}"; do
    TARGET_CONF_FILE="$SCRIPT_DIR/patch/$(basename "$PATCH_CONF_FILE" | sed -E 's;.template$;;')"
    cp -f "$PATCH_CONF_FILE" "$TARGET_CONF_FILE"

    sed -i -E 's;(//[[:space:]]*)?"auto_redirect":[^,]+,;"auto_redirect": true,;g' "$TARGET_CONF_FILE"
    sed -i -E 's;(//[[:space:]]*)?"auto_route":[^,]+,;"auto_route": true,;g' "$TARGET_CONF_FILE"
    sed -i -E 's;(//[[:space:]]*)?"route_address_set":;"route_address_set":;g' "$TARGET_CONF_FILE"
    sed -i -E 's;(//[[:space:]]*)?"route_exclude_address_set":;"route_exclude_address_set":;g' "$TARGET_CONF_FILE"
    sed -i -E 's;(//[[:space:]]*)?"default_mark":([^,]+),;// "default_mark":\2,;g' "$TARGET_CONF_FILE"
    sed -i -E 's;(//[[:space:]]*)?"routing_mark":([^,]+),;// "routing_mark":\2,;g' "$TARGET_CONF_FILE"

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
  if [ $VBOX_IP_RULE_WITH_AUTO_REDIRECT -eq 0 ]; then
    vbox_setup_patch_configures_without_auto_redirect
  else
    vbox_setup_patch_configures_with_auto_redirect
  fi
else
  vbox_cleanup_patch_configures
fi
