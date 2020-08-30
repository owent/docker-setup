#!/bin/bash

# /home/router/etc/v2ray/update-geoip-geosite.sh

if [ -e "/opt/podman" ]; then
    export PATH=/opt/podman/bin:/opt/podman/libexec:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/bin/site_perl:/usr/bin/vendor_perl:/usr/bin/core_perl
else
    export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/bin/site_perl:/usr/bin/vendor_perl:/usr/bin/core_perl
fi

mkdir -p /home/router/etc/v2ray ;
cd /home/router/etc/v2ray ;


# patch for podman 1.6.3 restart BUG
#   @see https://bbs.archlinux.org/viewtopic.php?id=251410
#   @see https://github.com/containers/libpod/issues/4522


/home/router/v2ray/create-v2ray-pod.sh

podman container inspect v2ray > /dev/null 2>&1
if [ $? -eq 0 ]; then

    if [ -e "geoip.dat" ]; then
        rm -f "geoip.dat";
    fi
    curl -k -L --retry 10 --retry-max-time 1800 "https://github.com/owent/update-geoip-geosite/releases/download/latest/geoip.dat" -o geoip.dat ;
    if [ $? -eq 0 ]; then
        podman cp geoip.dat v2ray:/usr/local/v2ray/bin/geoip.dat ;
    fi

    if [ -e "geosite.dat" ]; then
        rm -f "geosite.dat";
    fi
    curl -k -L --retry 10 --retry-max-time 1800 "https://github.com/owent/update-geoip-geosite/releases/download/latest/geosite.dat" -o geosite.dat ;
    if [ $? -eq 0 ]; then
        podman cp geosite.dat v2ray:/usr/local/v2ray/bin/geosite.dat ;
    fi

    systemctl disable v2ray ;
    systemctl stop v2ray ;
    systemctl enable v2ray ;
    systemctl start v2ray ;
else
    chmod +x /home/router/v2ray/create-v2ray-pod.sh;
    /home/router/v2ray/create-v2ray-pod.sh ;
fi

curl -k -L --retry 10 --retry-max-time 1800 "https://github.com/owent/update-geoip-geosite/releases/download/latest/ipv4_cn.ipset" -o ipv4_cn.ipset
if [ $? -eq 0 ]; then
    ipset list GEOIP_IPV4_CN > /dev/null 2>&1 ;
    if [ $? -eq 0 ]; then
        ipset flush GEOIP_IPV4_CN;
    else
        ipset create GEOIP_IPV4_CN hash:net family inet;
    fi

    cat ipv4_cn.ipset | ipset restore ;
fi

curl -k -L --retry 10 --retry-max-time 1800 "https://github.com/owent/update-geoip-geosite/releases/download/latest/ipv4_hk.ipset" -o ipv4_hk.ipset
if [ $? -eq 0 ]; then
    ipset list GEOIP_IPV4_HK > /dev/null 2>&1 ;
    if [ $? -eq 0 ]; then
        ipset flush GEOIP_IPV4_HK;
    else
        ipset create GEOIP_IPV4_HK hash:net family inet;
    fi

    cat ipv4_hk.ipset | ipset restore ;
fi

curl -k -L --retry 10 --retry-max-time 1800 "https://github.com/owent/update-geoip-geosite/releases/download/latest/ipv6_cn.ipset" -o ipv6_cn.ipset
if [ $? -eq 0 ]; then
    ipset list GEOIP_IPV6_CN > /dev/null 2>&1 ;
    if [ $? -eq 0 ]; then
        ipset flush GEOIP_IPV6_CN;
    else
        ipset create GEOIP_IPV6_CN hash:net family inet6;
    fi

    cat ipv6_cn.ipset | ipset restore ;
fi

curl -k -L --retry 10 --retry-max-time 1800 "https://github.com/owent/update-geoip-geosite/releases/download/latest/ipv6_hk.ipset" -o ipv6_hk.ipset
if [ $? -eq 0 ]; then
    ipset list GEOIP_IPV6_HK > /dev/null 2>&1 ;
    if [ $? -eq 0 ]; then
        ipset flush GEOIP_IPV6_HK;
    else
        ipset create GEOIP_IPV6_HK hash:net family inet6;
    fi

    cat ipv6_hk.ipset | ipset restore ;
fi

curl -k -L --retry 10 --retry-max-time 1800 "https://github.com/owent/update-geoip-geosite/releases/download/latest/dnsmasq-blacklist.conf" -o dnsmasq-blacklist.conf
if [ $? -eq 0 ]; then
    cp -f dnsmasq-blacklist.conf /etc/dnsmasq.d/10-dnsmasq-blacklist.router.conf
    ipset list DNSMASQ_GFW_IPV4 > /dev/null 2>&1 ;
    if [ $? -eq 0 ]; then
        ipset flush DNSMASQ_GFW_IPV4;
    else
        ipset create DNSMASQ_GFW_IPV4 hash:ip family inet;
    fi

    ipset list DNSMASQ_GFW_IPV6 > /dev/null 2>&1 ;
    if [ $? -eq 0 ]; then
        ipset flush DNSMASQ_GFW_IPV6;
    else
        ipset create DNSMASQ_GFW_IPV6 hash:ip family inet6;
    fi

    systemctl restart dnsmasq ;
fi

