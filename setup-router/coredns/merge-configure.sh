#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [[ "x$ROUTER_HOME" == "x" ]]; then
  source "$SCRIPT_DIR/../configure-router.sh"
fi

if [[ "x$RUN_USER" == "x" ]]; then
  RUN_USER=$(id -un)
fi
RUN_HOME=$(cat /etc/passwd | awk "BEGIN{FS=\":\"} \$1 == \"$RUN_USER\" { print \$6 }")

if [[ "x$RUN_HOME" == "x" ]]; then
  RUN_HOME="$HOME"
fi

if [[ "x$COREDNS_ETC_DIR" == "x" ]]; then
  export COREDNS_ETC_DIR="$RUN_HOME/coredns/etc"
fi
mkdir -p "$COREDNS_ETC_DIR"

echo "" >"$COREDNS_ETC_DIR/Corefile"

for CONFIGURE_FILE in "$SCRIPT_DIR/"*.router.coredns.conf; do
  cat "$CONFIGURE_FILE" >>"$COREDNS_ETC_DIR/Corefile"
done

if [[ "x$GEOIP_GEOSITE_ETC_DIR" != "x" ]] && [[ -e "$GEOIP_GEOSITE_ETC_DIR/coredns-blacklist.conf" ]]; then
  cat "$GEOIP_GEOSITE_ETC_DIR/coredns-blacklist.conf" >>"$COREDNS_ETC_DIR/Corefile"
fi

# if [[ "x$GEOIP_GEOSITE_ETC_DIR" != "x" ]] && [[ -e "$GEOIP_GEOSITE_ETC_DIR/coredns-accelerated-cn.conf" ]]; then
#   cat "$GEOIP_GEOSITE_ETC_DIR/coredns-accelerated-cn.conf" >>"$COREDNS_ETC_DIR/Corefile"
# fi
#
# if [[ "x$GEOIP_GEOSITE_ETC_DIR" != "x" ]] && [[ -e "$GEOIP_GEOSITE_ETC_DIR/coredns-special-cn.conf" ]]; then
#   cat "$GEOIP_GEOSITE_ETC_DIR/coredns-special-cn.conf" >>"$COREDNS_ETC_DIR/Corefile"
# fi

python3 "$SCRIPT_DIR/merge-service-block.py" "$COREDNS_ETC_DIR/Corefile" "$COREDNS_ETC_DIR/Corefile"

nmcli --fields NAME,TYPE connection show | grep 'pppoe'
if [ $? -ne 0 ]; then
  bash "$SCRIPT_DIR/replace-nextdns-ips.sh"
fi
