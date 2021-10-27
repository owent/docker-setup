FROM docker.io/library/library/ubuntu:18.04

ENV PATH="/opt/bin:$PATH"

LABEL maintainer "OWenT <admin@owent.net>"

# EXPOSE 36000/tcp
# EXPOSE 36000/udp
EXPOSE 22/tcp
EXPOSE 22/udp

COPY . /opt/docker-setup
RUN /bin/bash /opt/docker-setup/replace-source.sh ;                                                                         \
    if [ -e '/etc/dpkg/dpkg.cfg.d/excludes' ]; then                                                                         \
    sed -i '/^path-exclude=\/usr\/share\/man\// s|^|#|' /etc/dpkg/dpkg.cfg.d/excludes ;                                     \
    fi                                                                                                                      \
    apt update; apt install -y --reinstall apt coreutils bash sed procps;                                                   \
    apt install -y man-db locales tzdata less iproute2 gawk lsof systemd-cron openssh-client openssh-server systemd dnsutils ; \
    apt install -y vim wget curl ca-certificates telnet iotop htop knot-dnsutils  ;                                         \
    apt install -y traceroute tcptraceroute tcpdump netcat-openbsd ncat nftables;                                           \
    localectl set-locale LANGUAGE=en_US.UTF-8; localectl set-locale LANG=en_GB.utf8 ;                                       \
    timedatectl set-timezone Asia/Shanghai;                                                                                 \
    timedatectl set-ntp true;                                                                                               \
    systemctl enable systemd-timesyncd.service || true ;                                                                    \
    systemctl start systemd-timesyncd.service || true ;                                                                     \
    # hwclock -w;                                                                                                           \
    # ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime ;                                                             \
    /bin/bash /opt/docker-setup/debian.install-devtools.sh;                                                                 \
    /bin/bash /opt/docker-setup/cleanup.devtools.sh

# CMD /sbin/init