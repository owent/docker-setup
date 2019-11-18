# FROM registry.centos.org/centos/centos:8
FROM docker.io/library/centos:8

COPY setup-router /opt/docker-setup
# RUN dnf install -y vim dnsmasq dnsmasq-utils ppp dhcp-server dhcp-client ca-certificates ipset;         \
RUN dnf install -y vim dnsmasq dnsmasq-utils ppp  ca-certificates ipset;                                \
    /opt/docker-setup/setup-router/setup-dnsmasq.sh ;                                                   \
    /opt/docker-setup/setup-router/setup-dhcp.sh ;                                                      \
    /opt/docker-setup/setup-router/setup-ppp.sh ;                                                       \
    dnf clean all

# CMD /sbin/init

# sudo podman/docker run --network=host --cap-add NET_ADMIN --cap-add SYS_ADMIN -d 0f3e07c0138f /sbin/init