#!/bin/bash

# /home/router/etc/v2ray/update-geoip-geosite.sh

export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/bin/site_perl:/usr/bin/vendor_perl:/usr/bin/core_perl

if [ -e "/opt/podman" ]; then
    export PATH=/opt/podman/bin:/opt/podman/libexec:$PATH
fi

if [ -e "/opt/nftables/sbin" ]; then
    export PATH=/opt/nftables/sbin:$PATH
fi

mkdir -p /home/router/etc/v2ray ;
cd /home/router/etc/v2ray ;

if [ -e "geoip.dat" ]; then
    rm -f "geoip.dat";
fi
curl -k -qsL "https://github.com/owent/update-geoip-geosite/releases/download/latest/geoip.dat" -o geoip.dat ;
if [ $? -eq 0 ]; then
    podman cp geoip.dat v2ray:/usr/bin/v2ray/geoip.dat ;
fi

if [ -e "geosite.dat" ]; then
    rm -f "geosite.dat";
fi
curl -k -qsL "https://github.com/owent/update-geoip-geosite/releases/download/latest/geosite.dat" -o geosite.dat ;
if [ $? -eq 0 ]; then
    podman cp geosite.dat v2ray:/usr/bin/v2ray/geosite.dat ;
fi

systemctl disable v2ray ;
systemctl stop v2ray ;
systemctl enable v2ray ;
systemctl start v2ray ;
