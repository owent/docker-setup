# FROM registry.centos.org/centos/centos:8
FROM docker.io/library/centos:8

LABEL maintainer "OWenT <admin@owent.net>"

COPY setup-router /opt/docker-setup
COPY replace-source.sh /opt/docker-setup/replace-source.sh
# RUN dnf install -y vim dnsmasq dnsmasq-utils ppp dhcp-server dhcp-client ca-certificates ipset;         \
RUN /bin/bash /opt/docker-setup/replace-source.sh ;                                             \
    timedatectl set-timezone Asia/Shanghai;                                                     \
    timedatectl set-ntp true;                                                                   \
    systemctl enable systemd-timesyncd.service || true ;                                        \
    systemctl start systemd-timesyncd.service || true ;                                         \
    # hwclock -w;                                                                               \
    dnf update -y ;                                                                             \
    dnf install -y vim dnsmasq dnsmasq-utils ppp ca-certificates ipset nftables ;               \
    dnf install -y NetworkManager NetworkManager-tui NetworkManager-wifi NetworkManager-ppp ;   \
    dnf install -y NetworkManager-wwan NetworkManager-bluetooth chrony;                         \
    dnf install -y traceroute knot-utils tcpdump htop iotop nmap-ncat;                          \
    dnf clean all

CMD [ "/bin/bash", "/opt/docker-setup/setup-router/setup-services.sh" ]

# https://developers.redhat.com/blog/2019/04/24/how-to-run-systemd-in-a-container/
# sudo podman/docker run --network=host --cap-add NET_ADMIN --cap-add SYS_ADMIN -v /sys/fs/cgroup:/sys/fs/cgroup -d 0f3e07c0138f /sbin/init
# sudo podman run --network=host --cap-add NET_ADMIN --cap-add SYS_ADMIN –systemd=true -d 0f3e07c0138f /sbin/init