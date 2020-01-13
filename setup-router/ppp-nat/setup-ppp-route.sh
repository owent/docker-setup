#!/bin/bash

# /home/router/ppp-nat/setup-ppp-route.sh

if [ -e "/opt/nftables/sbin" ]; then
    export PATH=/opt/nftables/sbin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/bin/site_perl:/usr/bin/vendor_perl:/u    sr/bin/core_perl
else
    export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/bin/site_perl:/usr/bin/vendor_perl:/usr/bin/core_perl
fi

cd "$(dirname "${BASH_SOURCE[0]}")" ;

while [ ! -z "$(ip route show default 2>/dev/null)" ]; do
    ip route delete default ;
done
# ip route add default via XXX dev ppp0 ;
ip route add default dev ppp0 ;

chmod +x /home/router/ppp-nat/setup-nat-ssh.sh ;
/bin/bash /home/router/ppp-nat/setup-nat-ssh.sh ;