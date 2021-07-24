#!/bin/bash

# /home/router/v2ray/create-v2ray-pod.sh

if [ -e "/opt/podman" ]; then
    export PATH=/opt/podman/bin:/opt/podman/libexec:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/bin/site_perl:/usr/bin/vendor_perl:/usr/bin/core_perl
else
    export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/bin/site_perl:/usr/bin/vendor_perl:/usr/bin/core_perl
fi

mkdir -p /home/router/etc/v2ray ;
cd /home/router/etc/v2ray ;

systemctl disable v2ray ;
systemctl stop v2ray ;

podman container inspect v2ray > /dev/null 2>&1
if [[ $? -eq 0 ]]; then
    podman stop v2ray
    podman rm -f v2ray
fi

if [[ "x$V2RAY_UPDATE" != "x" ]]; then
    podman image inspect docker.io/owt5008137/proxy-with-geo:latest > /dev/null 2>&1
    if [[ $? -eq 0 ]]; then
        podman image rm -f docker.io/owt5008137/proxy-with-geo:latest ;
    fi
fi

podman pull docker.io/owt5008137/proxy-with-geo:latest ;

podman run -d --name v2ray --cap-add=NET_ADMIN --network=host --security-opt label=disable  \
    --mount type=bind,source=/home/router/etc/v2ray,target=/usr/local/v2ray/etc,ro=true     \
    --mount type=bind,source=/data/logs/v2ray,target=/data/logs/v2ray                       \
    --mount type=bind,source=/home/router/etc/v2ray/ssl,target=/usr/local/v2ray/ssl,ro=true \
    docker.io/owt5008137/proxy-with-geo:latest v2ray -config=/usr/local/v2ray/etc/config.json ;

podman cp v2ray:/usr/local/v2ray/share/geo-all.tar.gz geo-all.tar.gz ;
if [[ $? -eq 0 ]]; then
    tar -axvf geo-all.tar.gz ;

    if [[ $? -eq 0 ]]; then
        ipset list GEOIP_IPV4_CN > /dev/null 2>&1 ;
        if [[ $? -eq 0 ]]; then
            ipset flush GEOIP_IPV4_CN;
        else
            ipset create GEOIP_IPV4_CN hash:net family inet;
        fi

        cat ipv4_cn.ipset | ipset restore ;

        # TODO Maybe nftable ip set 
    fi

    if [[ $? -eq 0 ]]; then
        ipset list GEOIP_IPV4_HK > /dev/null 2>&1 ;
        if [[ $? -eq 0 ]]; then
            ipset flush GEOIP_IPV4_HK;
        else
            ipset create GEOIP_IPV4_HK hash:net family inet;
        fi

        cat ipv4_hk.ipset | ipset restore ;

        # TODO Maybe nftable ip set 
    fi

    if [[ $? -eq 0 ]]; then
        ipset list GEOIP_IPV6_CN > /dev/null 2>&1 ;
        if [[ $? -eq 0 ]]; then
            ipset flush GEOIP_IPV6_CN;
        else
            ipset create GEOIP_IPV6_CN hash:net family inet6;
        fi

        cat ipv6_cn.ipset | ipset restore ;

        # TODO Maybe nftable ip set 
    fi

    if [[ $? -eq 0 ]]; then
        ipset list GEOIP_IPV6_HK > /dev/null 2>&1 ;
        if [[ $? -eq 0 ]]; then
            ipset flush GEOIP_IPV6_HK;
        else
            ipset create GEOIP_IPV6_HK hash:net family inet6;
        fi

        cat ipv6_hk.ipset | ipset restore ;

        # TODO Maybe nftable ip set 
    fi

    if [[ $? -eq 0 ]]; then
        cp -f dnsmasq-blacklist.conf /etc/dnsmasq.d/10-dnsmasq-blacklist.router.conf
        ipset list DNSMASQ_GFW_IPV4 > /dev/null 2>&1 ;
        if [[ $? -eq 0 ]]; then
            ipset flush DNSMASQ_GFW_IPV4;
        else
            ipset create DNSMASQ_GFW_IPV4 hash:ip family inet;
        fi

        ipset list DNSMASQ_GFW_IPV6 > /dev/null 2>&1 ;
        if [[ $? -eq 0 ]]; then
            ipset flush DNSMASQ_GFW_IPV6;
        else
            ipset create DNSMASQ_GFW_IPV6 hash:ip family inet6;
        fi

        systemctl restart dnsmasq ;
    fi
fi

podman generate systemd v2ray | \
sed "/ExecStart=/a ExecStartPost=/home/router/v2ray/setup-tproxy.sh" | \
sed "/ExecStop=/a ExecStopPost=/home/router/v2ray/cleanup-tproxy.sh" | \
tee /lib/systemd/system/v2ray.service

podman container stop v2ray ;

systemctl daemon-reload ;

# patch end
systemctl enable v2ray ;
systemctl start v2ray ;

