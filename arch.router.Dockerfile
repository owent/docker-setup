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
    pacman -Syy --noconfirm ca-certificates tzdata bash vim dnsmasq ppp pppusage dhcp dhcping ipset;            \
    ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime ;                                                   \
    locale-gen en_US.UTF-8 ;                                                                                    \
    localectl set-locale LANGUAGE=en_US.UTF-8 || true; localectl set-locale LANG=en_GB.utf8 || true;            \
    pacman -Syy --noconfirm procps-ng less iproute2 gawk lsof openssh systemd sudo which cronie;                \
    pacman -Syy --noconfirm wget curl inetutils iotop htop bind-tools knot httping findutils;                   \
    pacman -Syy --noconfirm traceroute tcpdump openbsd-netcat nmap networkmanager nftables ;                    \
    pacman -S -cc --noconfirm;                                                                                  \
    rm -rf /var/lib/pacman/sync/* /var/cache/pacman/pkg/* ;                                                     \
    echo "" > /var/log/pacman.log ;

CMD [ "/lib/systemd/systemd" ]
