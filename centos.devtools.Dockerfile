# CentOS 8 is EOL, use AlmaLinux 9 instead
# FROM registry.centos.org/centos/centos:8
# FROM docker.io/library/centos:8
FROM docker.io/library/almalinux:9

ENV PATH="/opt/bin:$PATH"

LABEL maintainer "OWenT <admin@owent.net>"

# EXPOSE 36000/tcp
# EXPOSE 36000/udp
EXPOSE 22/tcp
EXPOSE 22/udp

COPY . /opt/docker-setup
RUN /bin/bash /opt/docker-setup/replace-source.sh ;                                                                 \
    sed -i '/^tsflags=nodocs/ s|^|#|' /etc/dnf/dnf.conf || true ;                                                   \
    dnf reinstall -y coreutils bash gawk sed;                                                                       \
    dnf install -y vim curl wget perl unzip p7zip p7zip-plugins net-tools telnet iotop btop iproute nftables;       \
    dnf install -y man-db tzdata less lsof openssh-clients openssh-server systemd vim wget curl ca-certificates ;   \
    dnf install -y traceroute knot-utils tcpdump btop iotop nmap-ncat yq jq;                                        \
    localectl set-locale LANG=en_GB.utf8 ;                                                                          \
    timedatectl set-timezone Asia/Shanghai;                                                                         \
    timedatectl set-ntp true;                                                                                       \
    groupadd -g 29998 tools; useradd -u 29998 -g 29998 -m tools -s /bin/bash ;                                      \
    # hwclock -w;                                                                                                   \
    # ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime ;                                                     \
    /bin/bash /opt/docker-setup/centos.install-devtools.sh;                                                        \
    /bin/bash /opt/docker-setup/cleanup.devtools.sh


# CMD /sbin/init