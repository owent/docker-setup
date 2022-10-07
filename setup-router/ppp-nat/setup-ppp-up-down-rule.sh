#!/bin/bash

# $ROUTER_HOME/ppp-nat/setup-ppp-up-down-rule.sh
if [[ -e "/opt/nftables/sbin" ]]; then
  export PATH=/opt/nftables/sbin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/bin/site_perl:/usr/bin/vendor_perl:/u sr/bin/core_perl
else
  export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/bin/site_perl:/usr/bin/vendor_perl:/usr/bin/core_perl
fi

if [[ "x$ROUTER_HOME" == "x" ]]; then
  source "$(cd "$(dirname "$0")" && pwd)/../configure-router.sh"
fi

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
