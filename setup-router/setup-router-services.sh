#!/bin/bash

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
source "$SCRIPT_DIR/configure-router.sh"
cd "$SCRIPT_DIR"

if [[ -e "$SCRIPT_DIR/ppp-nat/setup-ppp-up-down-rule.sh" ]]; then
  # Setup pppd with NetworkMansger on host
  /bin/bash "$SCRIPT_DIR/ppp-nat/setup-ppp-up-down-rule.sh"
fi

# Notice: gateways's ip must match the configure in setup-dnsmasq.sh and setup-nat-ssh.sh
#             fd27:32d6:ac12:XXXX/64 for ipv6
#             172.23.X.X/16 for ipv4
if [[ "x$ROUTER_CONFIG_IPV6_INTERFACE" == "x" ]]; then
  if [[ "x$ROUTER_CONFIG_PPP_LINK_INTERFACE" != "x" ]]; then
    export ROUTER_CONFIG_IPV6_INTERFACE=$ROUTER_CONFIG_PPP_LINK_INTERFACE
  fi
fi

# Disable systemd-resolved
if [[ -e /etc/systemd/resolved.conf ]]; then
  sed -i -r 's/#?DNSStubListener[[:space:]]*=.*/DNSStubListener=no/g' /etc/systemd/resolved.conf

  systemctl disable systemd-resolved
  systemctl stop systemd-resolved
fi

if [[ -e /etc/dnsmasq.d ]]; then
  systemctl disable dnsmasq
  systemctl stop dnsmasq
fi

if [[ "x$ROUTER_CONFIG_ON_FINISH_RUN" != "x" ]]; then
  chmod +x "$ROUTER_CONFIG_ON_FINISH_RUN"
  "$ROUTER_CONFIG_ON_FINISH_RUN"
fi

if [[ -e /etc/sysctl.d/95-interface-forwarding.conf ]]; then
  sysctl -p /etc/sysctl.d/95-interface-forwarding.conf
fi
