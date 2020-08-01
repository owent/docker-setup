#!/bin/bash

# /home/router/v2ray/create-v2ray-pod.sh

if [ -e "/opt/podman" ]; then
    export PATH=/opt/podman/bin:/opt/podman/libexec:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/bin/site_perl:/usr/bin/vendor_perl:/usr/bin/core_perl
else
    export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/bin/site_perl:/usr/bin/vendor_perl:/usr/bin/core_perl
fi

mkdir -p /home/router/etc/v2ray ;
cd /home/router/etc/v2ray ;

if [ -e "geoip.dat" ]; then
    rm -f "geoip.dat";
fi
curl -k -L --retry 10 --retry-max-time 1800 "https://github.com/owent/update-geoip-geosite/releases/download/latest/geoip.dat" -o geoip.dat ;

if [ -e "geosite.dat" ]; then
    rm -f "geosite.dat";
fi
curl -k -L --retry 10 --retry-max-time 1800 "https://github.com/owent/update-geoip-geosite/releases/download/latest/geosite.dat" -o geosite.dat ;

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


systemctl disable v2ray ;
systemctl stop v2ray ;

podman container inspect v2ray > /dev/null 2>&1
if [ $? -eq 0 ]; then
    podman stop v2ray
    podman rm -f v2ray
fi

podman run -d --name v2ray -v /home/router/etc/v2ray:/etc/v2ray -v /data/logs/v2ray:/data/logs/v2ray \
    --cap-add=NET_ADMIN --network=host localhost/local-v2ray v2ray -config=/etc/v2ray/config.json ;

if [ -e "geoip.dat" ]; then
    podman cp geoip.dat v2ray:/usr/bin/v2ray/geoip.dat ;
fi
if [ -e "geosite.dat" ]; then
    podman cp geosite.dat v2ray:/usr/bin/v2ray/geosite.dat ;
fi

podman generate systemd v2ray | \
sed "/ExecStart=/a ExecStartPost=/home/router/v2ray/setup-tproxy.sh" | \
sed "/ExecStop=/a ExecStopPost=/home/router/v2ray/cleanup-tproxy.sh" | \
tee /lib/systemd/system/v2ray.service

systemctl daemon-reload ;

# patch end
systemctl enable v2ray ;
systemctl start v2ray ;

