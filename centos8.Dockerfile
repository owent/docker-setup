FROM registry.centos.org/centos/centos:latest
# FROM docker.io/library/centos:latest

COPY . /opt/docker-setup
RUN dnf install -y vim curl wget perl unzip lzip p7zip p7zip-plugins autoconf telnet iotop htop libtool pkgconfig m4 ; \
    dnf install -y net-tools python3 python3-setuptools python3-pip python3-devel info asciidoc xmlto zlib-devel;      \
    dnf install -y ca-certificates gcc gcc-c++ gdb valgrind automake make libcurl-devel expat-devel glibc glibc-devel; \
    dnf clean all

# CMD /sbin/init