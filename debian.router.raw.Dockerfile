FROM docker.io/library/debian:latest

LABEL maintainer "OWenT <admin@owent.net>"

RUN cp -f /etc/apt/sources.list /etc/apt/sources.list.bak ;                                                     \
    sed -i.1.bak -r "s;https?://.*/debian-security/?[[:space:]];http://mirrors.tencent.com/debian-security/ ;g" /etc/apt/sources.list ; \
    sed -i.1.bak -r "s;https?://.*/debian/?[[:space:]];http://mirrors.tencent.com/debian/ ;g" /etc/apt/sources.list ;      \
    cat /etc/apt/sources.list ;                                                                                 \
    apt update -y;                                                                                              \
    apt install -y procps locales tzdata less iproute2 gawk lsof systemd-cron openssh-client openssh-server systemd  ; \
    apt install -y vim wget curl ca-certificates telnet iotop htop knot-dnsutils dnsutils ;                     \
    apt install -y dnsmasq dnsmasq-utils ppp pppconfig pppoe pppoeconf ca-certificates ipset chrony ;           \
    apt install -y traceroute tcptraceroute tcpdump netcat-openbsd ncat network-manager nftables;               \
    localectl set-locale LANGUAGE=en_US.UTF-8; localectl set-locale LANG=en_GB.utf8 ;                           \
    timedatectl set-timezone Asia/Shanghai;                                                                     \
    timedatectl set-ntp true;                                                                                   \
    systemctl enable systemd-timesyncd.service || true ;                                                        \
    systemctl start systemd-timesyncd.service || true ;                                                         \
    # hwclock -w;                                                                                                 \
    # ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime ;                                                   \
    rm -rf /var/lib/apt/lists/*

CMD ["/lib/systemd/systemd"]

# https://github.com/owent-utils/docker-setup