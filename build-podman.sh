#!/bin/bash

WORKING_DIR="$PWD";

# Dependencies for Fedora, CentOS, RHEL, and related distributions
sudo dnf/yum install -y atomic-registries btrfs-progs-devel containernetworking-cni device-mapper-devel git glib2-devel glibc-devel glibc-static go golang-github-cpuguy83-go-md2man gpgme-devel iptables libassuan-devel libgpg-error-devel libseccomp-devel libselinux-devel make ostree-devel pkgconfig runc containers-common
sudo dnf/yum install -y automake bison e2fsprogs-devel fuse-devel libtool xz-devel zlib-devel

# Dependencies for Debian, Ubuntu, and related distributions
sudo apt install -y btrfs-tools git golang-go go-md2man iptables libassuan-dev libc6-dev libdevmapper-dev libglib2.0-dev libgpgme-dev libgpg-error-dev libostree-dev libprotobuf-dev libprotobuf-c-dev libseccomp-dev libselinux1-dev libsystemd-dev pkg-config runc uidmap
sudo apt install -y automake bison e2fsprogs e2fslibs-dev fuse libfuse-dev libgpgme-dev liblzma-dev libtool zlib1g libapparmor-dev


# Kernel setup
## Make sure that the Linux kernel supports user namespaces:

# ```bash
# > zgrep CONFIG_USER_NS /proc/config.gz
# CONFIG_USER_NS=y
# 
# # if not shown as upper
# echo 'kernel.unprivileged_userns_clone=1' > /etc/sysctl.d/userns.conf
# sudo sysctl kernel.unprivileged_userns_clone=1
# ```


# https://podman.io/getting-started/installation

PODMAN_INSTALL_PREFIX=/opt/podman
PODMAN_ETC_PREFIX=/etc
PODMAN_OSTREE_VERSION=2019.5 ;
PODMAN_GOLANG_URL=https://dl.google.com/go/go1.13.4.linux-amd64.tar.gz ;
PODMAN_COMMON_VERSION=v2.0.3;
PODMAN_RUNC_VERSION=v1.0.0-rc9;
PODMAN_CNI_PLUGINS_VERSION=v0.8.3 ;
PODMAN_LIBPOD_VERSION=v1.6.3 ;

PODMAN_GOLANG_BASENAME=$(basename $PODMAN_GOLANG_URL);
PODMAN_GOLANG_VERSION=$(echo "$PODMAN_GOLANG_BASENAME" | awk '{if(match($0, /go[0-9]*\.[0-9]*(\.[0-9]*)/, m)) {print m[0];}}') ;
sudo mkdir -p "$PODMAN_INSTALL_PREFIX/bin";
export PATH="$PODMAN_INSTALL_PREFIX/bin:$PATH";
export GOPATH="$PODMAN_INSTALL_PREFIX/$PODMAN_GOLANG_VERSION/go";

### ostree
git clone -b $PODMAN_OSTREE_VERSION --depth=100 https://github.com/ostreedev/ostree "$WORKING_DIR/ostree" ;
cd "$WORKING_DIR/ostree" ;
git submodule update -f --init ;
./autogen.sh --prefix=$PODMAN_INSTALL_PREFIX --libdir=$PODMAN_INSTALL_PREFIX/lib64 --sysconfdir=$PODMAN_ETC_PREFIX ;
sed -i '/.*--nonet.*/d' ./Makefile-man.am ;
make -j ;
sudo make install ;

### golang
if [ ! -e "$PODMAN_INSTALL_PREFIX/$PODMAN_GOLANG_VERSION/go" ]; then
    sudo mkdir -p "$PODMAN_INSTALL_PREFIX/$PODMAN_GOLANG_VERSION";
    cd "$PODMAN_INSTALL_PREFIX/$PODMAN_GOLANG_VERSION";
    wget --no-check-certificate $PODMAN_GOLANG_URL -O "$PODMAN_GOLANG_BASENAME";
    tar -axvf "$PODMAN_GOLANG_BASENAME" ;
    for LINK_FILE in $(find "$PODMAN_INSTALL_PREFIX/$PODMAN_GOLANG_VERSION/go/bin" -name "*") ; do
        LINK_BASENAME="$(basename "$LINK_FILE")";
        if [ -e "$PODMAN_INSTALL_PREFIX/bin/$LINK_BASENAME" ]; then
            rm -f "$PODMAN_INSTALL_PREFIX/bin/$LINK_BASENAME";
        fi

        ln -sf "$LINK_FILE" "$PODMAN_INSTALL_PREFIX/bin/$LINK_BASENAME";
    done
fi

### conmon
git clone -b $PODMAN_COMMON_VERSION --depth=100 https://github.com/containers/conmon.git "$WORKING_DIR/conmon" ;
cd "$WORKING_DIR/conmon" ;
make -j ;
sudo make podman -j ;

### runc
sudo mkdir -p "$GOPATH/src/github.com/opencontainers";
git clone -b $PODMAN_RUNC_VERSION --depth=100 https://github.com/opencontainers/runc.git "$GOPATH/src/github.com/opencontainers/runc" ;
cd "$GOPATH/src/github.com/opencontainers/runc" ;
make BUILDTAGS="selinux seccomp" -j ;
sudo cp -f runc "$PODMAN_INSTALL_PREFIX/bin/runc" ;

### CNI plugins
sudo mkdir -p "$GOPATH/src/github.com/containernetworking";
git clone -b $PODMAN_CNI_PLUGINS_VERSION --depth=100 https://github.com/containernetworking/plugins.git "$GOPATH/src/github.com/containernetworking/plugins" ;
cd "$GOPATH/src/github.com/containernetworking/plugins" ;
./build_linux.sh ;
sudo mkdir -p "$PODMAN_INSTALL_PREFIX/libexec/cni" ;
sudo cp bin/* "$PODMAN_INSTALL_PREFIX/libexec/cni" ;

### Setup CNI networking
sudo mkdir -p $PODMAN_ETC_PREFIX/cni/net.d ;
curl -qsSL https://raw.githubusercontent.com/containers/libpod/master/cni/87-podman-bridge.conflist | sudo tee $PODMAN_ETC_PREFIX/cni/net.d/99-loopback.conf ;

### Add configuration
sudo mkdir -p $PODMAN_ETC_PREFIX/containers
sudo curl https://raw.githubusercontent.com/projectatomic/registries/master/registries.fedora -o $PODMAN_ETC_PREFIX/containers/registries.conf ;
sudo curl https://raw.githubusercontent.com/containers/skopeo/master/default-policy.json -o $PODMAN_ETC_PREFIX/containers/policy.json ;

### Optional packages
### libpod
sudomkdir -p "$GOPATH/src/github.com/containers" ;
git clone -b $PODMAN_LIBPOD_VERSION --depth=100 https://github.com/containers/libpod/ $GOPATH/src/github.com/containers/libpod
cd $GOPATH/src/github.com/containers/libpod
make BUILDTAGS="selinux seccomp systemd"
sudo make install PREFIX=$PODMAN_INSTALL_PREFIX

#### Build Tags
#### https://podman.io/getting-started/installation#build-tags

### Configuration files
sudo mkdir -p "$PODMAN_ETC_PREFIX/containers" ;
sudo mkdir -p "/usr/share/containers" ;
sudo curl https://src.fedoraproject.org/rpms/skopeo/raw/master/f/registries.conf -o $PODMAN_ETC_PREFIX/containers/registries.conf
echo "/usr/share/rhel/secrets:/run/secrets" | sudo tee "/usr/share/containers/mounts.conf" ;
sudo curl https://src.fedoraproject.org/rpms/skopeo/raw/master/f/seccomp.json -o /usr/share/containers/seccomp.json ;
sudo curl https://raw.githubusercontent.com/containers/skopeo/master/default-policy.json -o "$PODMAN_ETC_PREFIX/containers/policy.json" ;
