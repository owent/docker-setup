#!/bin/bash

# /home/router/ppp-nat/setup-ppp-route.sh
# @see https://linux.die.net/man/8/pppd
#
# When the ppp link comes up, this script is called with the following
# parameters
#       $1      the interface name used by pppd (e.g. ppp3)
#       $2      the tty device name
#       $3      the tty device speed
#       $4      the local IP address for the interface
#       $5      the remote IP address
#       $6      the parameter specified by the 'ipparam' option to pppd
#

if [ -e "/opt/nftables/sbin" ]; then
    export PATH=/opt/nftables/sbin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/bin/site_perl:/usr/bin/vendor_perl:/u    sr/bin/core_perl
else
    export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/bin/site_perl:/usr/bin/vendor_perl:/usr/bin/core_perl
fi

cd "$(dirname "${BASH_SOURCE[0]}")" ;

while [ ! -z "$(ip route show default 2>/dev/null)" ]; do
    ip route delete default ;
done
# ip route add default via XXX dev $1 ;
ip route add default via $5 dev $1 ;

chmod +x /home/router/ppp-nat/setup-nat-ssh.sh ;
/bin/bash /home/router/ppp-nat/setup-nat-ssh.sh ;