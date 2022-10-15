#!/bin/bash

# $ROUTER_HOME/ppp-nat/setup-ppp-up-down-rule.sh
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
source "$(dirname "$SCRIPT_DIR")/configure-router.sh"

function mklink_script() {
  if [[ -e "$2" ]]; then
    rm -f "$2"
  fi

  chmod +x "$1"
  ln -sf "$1" "$2"
}

mklink_script $ROUTER_HOME/ppp-nat/cleanup-ppp-route-ipv4.sh /etc/ppp/ip-down.d/99-cleanup-ppp-route.sh
mklink_script $ROUTER_HOME/ppp-nat/setup-ppp-route-ipv4.sh /etc/ppp/ip-up.d/99-setup-ppp-route.sh

mklink_script $ROUTER_HOME/ppp-nat/cleanup-ppp-route-ipv6.sh /etc/ppp/ipv6-down.d/99-cleanup-ppp-route.sh
mklink_script $ROUTER_HOME/ppp-nat/setup-ppp-route-ipv6.sh /etc/ppp/ipv6-up.d/99-setup-ppp-route.sh

chmod +x $ROUTER_HOME/ppp-nat/setup-nft-security.sh
/bin/bash $ROUTER_HOME/ppp-nat/setup-nft-security.sh

chmod +x $ROUTER_HOME/ppp-nat/setup-nat-ssh.sh
/bin/bash $ROUTER_HOME/ppp-nat/setup-nat-ssh.sh
