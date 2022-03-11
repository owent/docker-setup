#!/bin/bash

SCRIPT_DIR="$(
  cd "$(dirname "$0")"
  pwd
)"

echo "bind [::]:$SMARTDNS_DNS_PORT
bind-tcp [::]:$SMARTDNS_DNS_PORT" >"$SMARTDNS_ETC_DIR/smartdns.conf"

cat "$SCRIPT_DIR/smartdns.origin.conf" >>"$SMARTDNS_ETC_DIR/smartdns.conf"

if [[ "x$GEOIP_GEOSITE_ETC_DIR" != "x" ]] && [[ -e "$GEOIP_GEOSITE_ETC_DIR/smartdns-blacklist.conf" ]]; then
  cat "$GEOIP_GEOSITE_ETC_DIR/smartdns-blacklist.conf" >>"$SMARTDNS_ETC_DIR/smartdns.conf"
fi
