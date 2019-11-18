FROM docker.io/library/library/ubuntu:18.04

ENV PATH="/opt/bin:$PATH"

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
    apt install -y man-db locales tzdata less iproute2 gawk lsof cron openssh-client openssh-server systemd systemd-cron ;  \
    apt install -y vim wget curl ca-certificates telnet iotop htop ;                                                        \
    locale-gen en_US.UTF-8; localectl set-locale LANG=en_GB.utf8 ;                                                          \
    ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime ;                                                               \
    /bin/bash /opt/docker-setup/ubuntu.install-devtools.sh;                                                                 \
    /bin/bash /opt/docker-setup/cleanup.devtools.sh


# CMD /sbin/init