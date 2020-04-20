# FROM registry.centos.org/centos/centos:8
FROM docker.io/library/centos:8

ENV PATH="/opt/bin:$PATH"

LABEL maintainer "OWenT <admin@owent.net>"

# EXPOSE 36000/tcp
# EXPOSE 36000/udp
EXPOSE 22/tcp
EXPOSE 22/udp

COPY . /opt/docker-setup
RUN /bin/bash /opt/docker-setup/replace-source.sh ;                                                                 \
    sed -i '/^tsflags=nodocs/ s|^|#|' /etc/yum.conf ;                                                               \
    dnf reinstall -y coreutils bash gawk sed;                                                                       \
    dnf install -y vim curl wget perl unzip lzip p7zip p7zip-plugins net-tools telnet iotop htop iproute nftables;  \
    dnf install -y man-db tzdata less lsof openssh-clients openssh-server systemd vim wget curl ca-certificates  ;  \
    dnf install -y traceroute knot-utils tcpdump htop iotop nmap-ncat  ;                                            \
    localectl set-locale LANG=en_GB.utf8 ;                                                                          \
    timedatectl set-timezone Asia/Shanghai;                                                                     \
    timedatectl set-ntp true;                                                                                   \
    # hwclock -w;                                                                                                 \
    # ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime ;                                                       \
    /bin/bash /opt/docker-setup/centos8.install-devtools.sh;                                                        \
    /bin/bash /opt/docker-setup/cleanup.devtools.sh


# CMD /sbin/init