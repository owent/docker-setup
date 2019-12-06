FROM docker.io/library/debian:latest

COPY setup-router /opt/docker-setup
COPY replace-source.sh /opt/docker-setup/replace-source.sh
# RUN dnf install -y vim dnsmasq dnsmasq-utils ppp dhcp-server dhcp-client ca-certificates ipset;         \
RUN /bin/bash /opt/docker-setup/replace-source.sh                                                   \
    apt update -y;                                                                                              \
    apt install -y procps locales tzdata less iproute2 gawk lsof cron openssh-client openssh-server systemd  ;  \
    apt install -y vim wget curl ca-certificates telnet iotop htop knot-dnsutils dnsutils systemd-cron ;        \
    apt install -y dnsmasq dnsmasq-utils ppp pppconfig pppoe pppoeconf ca-certificates ipset;                   \
    apt install -y traceroute tcptraceroute tcpdump netcat-openbsd ncat network-manager nftables ;              \
    localectl set-locale LANGUAGE=en_US.UTF-8; localectl set-locale LANG=en_GB.utf8 ;                           \
    ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime ;                                                   \
    rm -rf /var/lib/apt/lists/*

CMD ["/bin/bash", "/opt/docker-setup/setup-router/setup-services.sh" ]

# https://developers.redhat.com/blog/2019/04/24/how-to-run-systemd-in-a-container/
## setup tmpfs for /run, /run/lock, /tmp, /sys/fs/cgroup/systemd, /var/lib/journal
# sudo podman/docker run --network=host --cap-add NET_ADMIN --cap-add SYS_ADMIN -v /sys/fs/cgroup:/sys/fs/cgroup -d 0f3e07c0138f /sbin/init
# sudo podman run --network=host --cap-add NET_ADMIN --cap-add SYS_ADMIN –systemd=true -d 0f3e07c0138f /sbin/init