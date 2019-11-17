FROM registry.centos.org/centos/centos:latest
# FROM docker.io/library/centos:latest

COPY setup-router /opt/docker-setup
RUN dnf install -y vim dnsmasq dnsmasq-utils ppp dhcp-server dhcp-client ca-certificates ipset;         \
    /opt/docker-setup/setup-router/setup-dnsmasq.sh ;                                                   \
    /opt/docker-setup/setup-router/setup-dhcp.sh ;                                                      \
    /opt/docker-setup/setup-router/setup-ppp.sh ;                                                       \
    dnf clean all

# CMD /sbin/init