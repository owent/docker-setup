#!/bin/bash

NFTABLES_VERSION=1.1.1
LIBNFTNL_VERSION=1.2.8
LIBNML_VERSION=1.0.5

NFTABLES_INSTALL_PREFIX=/opt/nftables
NFTABLES_URL="https://netfilter.org/projects/nftables/files/nftables-$NFTABLES_VERSION.tar.xz"
LIBNFTNL_URL="https://netfilter.org/projects/libnftnl/files/libnftnl-$LIBNFTNL_VERSION.tar.xz"
LIBNML_URL="https://netfilter.org/projects/libmnl/files/libmnl-$LIBNML_VERSION.tar.bz2"

WORKING_DIR="$PWD"

grep -E -i "ubuntu|debian" /etc/os-release

#bison flex asciidoc libgmp-dev libreadline-dev libxtables-dev libjansson-dev

if [ $? -eq 0 ]; then
  # Dependencies for Debian, Ubuntu, and related distributions
  sudo apt install -y flex pkg-config python3 python3-setuptools python3-pip
  sudo apt install -y make automake bison e2fsprogs e2fslibs-dev fuse libfuse-dev libgpgme-dev liblzma-dev libtool zlib1g libapparmor-dev
  PODMAN_BUILD_MODE=apt
else
  # Dependencies for Fedora, CentOS, RHEL, and related distributions
  which dnf >/dev/null 2>&1
  if [ $? -eq 0 ]; then
    PODMAN_BUILD_MODE=dnf
  else
    PODMAN_BUILD_MODE=yum
  fi
  sudo $PODMAN_BUILD_MODE install -y atomic-registries btrfs-progs-devel containernetworking-cni device-mapper-devel git glib2-devel glibc-devel glibc-static go golang-github-cpuguy83-go-md2man gpgme-devel iptables libassuan-devel libgpg-error-devel libseccomp-devel libselinux-devel make ostree-devel pkgconfig runc containers-common
  sudo $PODMAN_BUILD_MODE install -y automake bison e2fsprogs-devel fuse-devel libtool xz-devel zlib-devel libbtrfs-dev fuse-overlayfs
fi

# build libmnl
cd "$WORKING_DIR"
curl -qsSL "$LIBNML_URL" -o "$WORKING_DIR/libmnl-$LIBNML_VERSION.tar.bz2"
tar -axvf "libmnl-$LIBNML_VERSION.tar.bz2"
cd "libmnl-$LIBNML_VERSION"
./configure --prefix=$NFTABLES_INSTALL_PREFIX --with-pic=yes
make -j
sudo make install

# build libnftnl
cd "$WORKING_DIR"
curl -qsSL "$LIBNFTNL_URL" -o "$WORKING_DIR/libnftnl-$LIBNFTNL_VERSION.tar.bz2"
tar -axvf "libnftnl-$LIBNFTNL_VERSION.tar.bz2"
cd "libnftnl-$LIBNFTNL_VERSION"
./configure --prefix=$NFTABLES_INSTALL_PREFIX --with-pic=yes PKG_CONFIG_PATH=$NFTABLES_INSTALL_PREFIX/lib/pkgconfig
make -j
sudo make install

# build nftables
cd "$WORKING_DIR"
curl -qsSL "$NFTABLES_URL" -o "$WORKING_DIR/nftables-$NFTABLES_VERSION.tar.bz2"
tar -axvf "nftables-$NFTABLES_VERSION.tar.bz2"
cd "nftables-$NFTABLES_VERSION"
./configure --prefix=$NFTABLES_INSTALL_PREFIX --with-xtables --with-json --with-python-bin --with-pic=yes PKG_CONFIG_PATH=$NFTABLES_INSTALL_PREFIX/lib/pkgconfig
sed -i 's/PYTHON_BIN\s*=\s*yes/PYTHON_BIN = python/g' py/Makefile # patch infinitely loop
make -j
sudo make install
