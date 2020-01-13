#!/bin/bash

# /home/router/ppp-nat/setup-ppp-up-down-rule.sh
if [ -e "/opt/nftables/sbin" ]; then
    export PATH=/opt/nftables/sbin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/bin/site_perl:/usr/bin/vendor_perl:/u    sr/bin/core_perl
else
    export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/bin/site_perl:/usr/bin/vendor_perl:/usr/bin/core_perl
fi

if [ -e "/etc/ppp/ip-down.d/99-cleanup-ppp-route.sh" ]; then
    rm -f "/etc/ppp/ip-down.d/99-cleanup-ppp-route.sh";
fi

chmod +x /home/router/ppp-nat/cleanup-ppp-route.sh ;
ln -s /home/router/ppp-nat/cleanup-ppp-route.sh /etc/ppp/ip-down.d/99-cleanup-ppp-route.sh ;

if [ -e "/etc/ppp/ip-up.d/99-setup-ppp-route.sh" ]; then
    rm -f "/etc/ppp/ip-up.d/99-setup-ppp-route.sh";
fi

chmod +x /home/router/ppp-nat/setup-ppp-route.sh ;
ln -s /home/router/ppp-nat/setup-ppp-route.sh /etc/ppp/ip-up.d/99-setup-ppp-route.sh ;

