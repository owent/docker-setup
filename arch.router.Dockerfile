# podman build --layers --force-rm --tag local-router -f arch.router.Dockerfile
# docker build --force-rm --tag local-router -f arch.router.Dockerfile .
# FROM docker.io/library/alpine:latest
FROM docker.io/library/archlinux:latest

LABEL maintainer "OWenT <admin@owent.net>"

RUN set -ex ;                                                                                                   \
    sed -i -r '/Server\s*=\s*.*tencent.com/d' /etc/pacman.d/mirrorlist;                                         \
    sed -i -r '/Server\s*=\s*.*aliyun.com/d' /etc/pacman.d/mirrorlist;                                          \
    sed -i '1i Server = http://mirrors.aliyun.com/archlinux/$repo/os/$arch' /etc/pacman.d/mirrorlist;           \
    sed -i '1i Server = https://mirrors.tencent.com/archlinux/$repo/os/$arch' /etc/pacman.d/mirrorlist;         \
    pacman -Syyu --noconfirm ;                                                                                  \
    yes y | pacman -S iptables nftables ebtables ipset chrony;                                                  \
    pacman -Syy --noconfirm ca-certificates tzdata bash vim dnsmasq ppp networkmanager;                         \
    pacman -Syy --noconfirm rp-pppoe;                                                                           \
    timedatectl set-timezone Asia/Shanghai;                                                                     \
    timedatectl set-ntp true;                                                                                   \
    systemctl enable systemd-timesyncd.service || true ;                                                        \
    systemctl start systemd-timesyncd.service || true ;                                                         \
    # hwclock -w;                                                                                               \
    # ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime ;                                                 \
    locale-gen en_US.UTF-8 ;                                                                                    \
    localectl set-locale LANGUAGE=en_US.UTF-8 || true; localectl set-locale LANG=en_GB.utf8 || true;            \
    pacman -Syy --noconfirm procps-ng less iproute2 gawk systemd which wget curl inetutils findutils;           \
    pacman -S -cc --noconfirm;                                                                                  \
    sed -i -r 's/#?DNSStubListener[[:space:]]*=.*/DNSStubListener=no/g'  /etc/systemd/resolved.conf ;           \
    rm -rf /var/lib/pacman/sync/* /var/cache/pacman/pkg/* ;                                                     \
    echo "" > /var/log/pacman.log ;


CMD [ "/lib/systemd/systemd" ]
