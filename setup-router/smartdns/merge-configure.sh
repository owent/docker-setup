#!/bin/bash

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
source "$(dirname "$SCRIPT_DIR")/configure-router.sh"

if [[ "x$SMARTDNS_ETC_DIR" == "x" ]]; then
  export SMARTDNS_ETC_DIR="$RUN_HOME/smartdns/etc"
fi
mkdir -p "$SMARTDNS_ETC_DIR"

echo "bind [::]:$SMARTDNS_DNS_PORT
bind-tcp [::]:$SMARTDNS_DNS_PORT" >"$SMARTDNS_ETC_DIR/smartdns.conf"

cat "$SCRIPT_DIR/smartdns.origin.conf" >>"$SMARTDNS_ETC_DIR/smartdns.conf"

for CONFIGURE_FILE in "$SCRIPT_DIR/"*.router.smartdns.conf; do
  cat "$CONFIGURE_FILE" >>"$SMARTDNS_ETC_DIR/smartdns.conf"
done

if [[ "x$SMARTDNS_APPEND_CONFIGURE" != "x" ]]; then
  echo "$SMARTDNS_APPEND_CONFIGURE" >>"$SMARTDNS_ETC_DIR/smartdns.conf"
fi

if [[ "x$GEOIP_GEOSITE_ETC_DIR" != "x" ]] && [[ -e "$GEOIP_GEOSITE_ETC_DIR/smartdns-blacklist.conf" ]]; then
  cat "$GEOIP_GEOSITE_ETC_DIR/smartdns-blacklist.conf" >>"$SMARTDNS_ETC_DIR/smartdns.conf"
fi

# if [[ "x$GEOIP_GEOSITE_ETC_DIR" != "x" ]] && [[ -e "$GEOIP_GEOSITE_ETC_DIR/smartdns-accelerated-cn.conf" ]]; then
#   cat "$GEOIP_GEOSITE_ETC_DIR/smartdns-accelerated-cn.conf" >>"$SMARTDNS_ETC_DIR/smartdns.conf"
# fi
#
# if [[ "x$GEOIP_GEOSITE_ETC_DIR" != "x" ]] && [[ -e "$GEOIP_GEOSITE_ETC_DIR/smartdns-special-cn.conf" ]]; then
#   cat "$GEOIP_GEOSITE_ETC_DIR/smartdns-special-cn.conf" >>"$SMARTDNS_ETC_DIR/smartdns.conf"
# fi
