#!/bin/bash

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
source "$SCRIPT_DIR/configure-router.sh"
cd "$SCRIPT_DIR"

if [[ -e "/lib/systemd/system" ]]; then
  export SETUP_SYSTEMD_SYSTEM_DIR=/lib/systemd/system
elif [[ -e "/usr/lib/systemd/system" ]]; then
  export SETUP_SYSTEMD_SYSTEM_DIR=/usr/lib/systemd/system
elif [[ -e "/etc/systemd/system" ]]; then
  export SETUP_SYSTEMD_SYSTEM_DIR=/etc/systemd/system
fi

if [[ "x$ROUTER_CONFIG_ENV_FILE" != "x" ]]; then
  source "$ROUTER_CONFIG_ENV_FILE"
fi

# export ROUTER_CONFIG_PPP_LINK_INTERFACE=<PPP wan interface> # enp1s0f3, wan0 ?
# export ROUTER_CONFIG_PPP_USERNAME=<PPPOE USER NAME>
# export ROUTER_CONFIG_PPP_PASSWORD=<PPPOE USER PASSWORD>

if [[ "x$ROUTER_CONFIG_PPP_LINK_INTERFACE" != "x" ]]; then
  /bin/bash "$SCRIPT_DIR/ppp-nat/setup-ppp.legacy.sh"
  systemctl daemon-reload
  systemctl enable pppd-$ROUTER_CONFIG_PPP_LINK_INTERFACE
  systemctl start pppd-$ROUTER_CONFIG_PPP_LINK_INTERFACE
else
  # Setup pppd with NetworkMansger on host
  /bin/bash "$SCRIPT_DIR/ppp-nat/setup-ppp-up-down-rule.sh"
fi

# Notice: gateways's ip must match the configure in setup-dnsmasq.sh and setup-nat-ssh.sh
#             fd27:32d6:ac12:XXXX/64 for ipv6
#             172.18.X.X/16 for ipv4
if [[ "x$ROUTER_CONFIG_IPV6_INTERFACE" == "x" ]]; then
  if [[ "x$ROUTER_CONFIG_PPP_LINK_INTERFACE" != "x" ]]; then
    export ROUTER_CONFIG_IPV6_INTERFACE=$ROUTER_CONFIG_PPP_LINK_INTERFACE
  fi
fi

# Disable systemd-resolved
sed -i -r 's/#?DNSStubListener[[:space:]]*=.*/DNSStubListener=no/g' /etc/systemd/resolved.conf

systemctl disable systemd-resolved
systemctl stop systemd-resolved

if [ $DNSMASQ_ENABLE_DNS -ne 0 ] || [ $DNSMASQ_ENABLE_DHCP -ne 0 ] || [ $DNSMASQ_ENABLE_IPV6_NDP -ne 0 ]; then
  /bin/bash "$SCRIPT_DIR/dnsmasq/setup-dnsmasq.sh"

  systemctl daemon-reload
  systemctl enable dnsmasq
else
  systemctl disable dnsmasq
  systemctl stop dnsmasq
fi

# Smartdns
if [ $SMARTDNS_ENABLE -ne 0 ]; then
  su "$SCRIPT_DIR/smartdns/create-smartdns-pod.sh" - tools
fi

if [[ "x$ROUTER_CONFIG_ON_FINISH_RUN" == "x" ]]; then
  chmod +x "$ROUTER_CONFIG_ON_FINISH_RUN"
  "$ROUTER_CONFIG_ON_FINISH_RUN"
fi
