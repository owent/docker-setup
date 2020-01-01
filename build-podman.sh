#!/bin/bash

WORKING_DIR="$PWD";
export PATH="$PATH:/sbin" ;

grep -E -i "ubuntu|debian" /etc/os-release ;

if [ $? -eq 0 ]; then
    # Dependencies for Debian, Ubuntu, and related distributions
    sudo apt install -y btrfs-tools git golang-go go-md2man iptables libassuan-dev libc6-dev libdevmapper-dev libglib2.0-dev libgpgme-dev libgpg-error-dev libostree-dev libprotobuf-dev libprotobuf-c-dev libseccomp-dev libselinux1-dev libsystemd-dev pkg-config runc uidmap
    sudo apt install -y make automake bison e2fsprogs e2fslibs-dev fuse libfuse-dev libgpgme-dev liblzma-dev libtool zlib1g libapparmor-dev
    PODMAN_BUILD_MODE=apt
else
    # Dependencies for Fedora, CentOS, RHEL, and related distributions
    which dnf > /dev/null 2>&1 ;
    if [ $? -eq 0 ]; then
        PODMAN_BUILD_MODE=dnf;
    else
        PODMAN_BUILD_MODE=yum;
    fi
    sudo $PODMAN_BUILD_MODE install -y atomic-registries btrfs-progs-devel containernetworking-cni device-mapper-devel git glib2-devel glibc-devel glibc-static go golang-github-cpuguy83-go-md2man gpgme-devel iptables libassuan-devel libgpg-error-devel libseccomp-devel libselinux-devel make ostree-devel pkgconfig runc containers-common
    sudo $PODMAN_BUILD_MODE install -y automake bison e2fsprogs-devel fuse-devel libtool xz-devel zlib-devel libbtrfs-dev fuse-overlayfs
fi

# Kernel setup
## Make sure that the Linux kernel supports user namespaces:

# ```bash
# > zgrep CONFIG_USER_NS /proc/config.gz
# CONFIG_USER_NS=y
# 
# # if not shown as upper
# # Note: cat /proc/sys/kernel/unprivileged_userns_clone or sudo sysctl kernel.unprivileged_userns_clone
# echo 'kernel.unprivileged_userns_clone=1' > /etc/sysctl.d/userns.conf
# sudo sysctl kernel.unprivileged_userns_clone=1
# ```


# https://podman.io/getting-started/installation

PODMAN_INSTALL_PREFIX=/opt/podman
PODMAN_ETC_PREFIX=/etc
PODMAN_OSTREE_VERSION=v2019.6 ;
# PODMAN_GOLANG_URL=https://dl.google.com/go/go1.13.5.linux-amd64.tar.gz ;
PODMAN_GOLANG_URL=https://mirrors.ustc.edu.cn/golang/go1.13.5.linux-amd64.tar.gz ;
PODMAN_CONMON_VERSION=v2.0.7;
PODMAN_RUNC_VERSION=v1.0.0-rc9;
PODMAN_CNI_PLUGINS_VERSION=v0.8.3 ;
PODMAN_LIBPOD_VERSION=v1.6.4 ;

PODMAN_GOLANG_BASENAME=$(basename $PODMAN_GOLANG_URL);
PODMAN_GOLANG_VERSION=$(echo "$PODMAN_GOLANG_BASENAME" | awk '{if(match($0, /go[0-9]*\.[0-9]*(\.[0-9]*)/, m)) {print m[0];}}') ;
sudo mkdir -p "$PODMAN_INSTALL_PREFIX/bin" && sudo chmod 777 "$PODMAN_INSTALL_PREFIX/bin";
export PATH="$PODMAN_INSTALL_PREFIX/bin:$PATH";
export GOPATH="$PODMAN_INSTALL_PREFIX/GOPATH";
export GOPROXY=https://goproxy.cn,direct ;
# export GOPROXY=https://mirrors.aliyun.com/goproxy/ ;
# export GOPROXY=http://mirrors.cloud.tencent.com/go/ ;
export GOPRIVATE=github.com ;
sudo mkdir -p "$GOPATH" && sudo chmod 777 "$GOPATH" ;

function git_clone_fetch() {
    if [ -e "$3/.git" ]; then
        cd "$3";
        git fetch --depth=100 origin "$1";
        if [ $? -ne 0 ]; then
            cd -;
            rm -rf "$3";
        else
            git clean -df ;
            git reset --hard "origin/$1" ;
            cd -;
        fi
    fi

    if [ ! -e "$3/.git" ]; then
        if [ -e "$3/.git" ]; then
            rm -rf "$3" ;
        fi

        git clone -b "$1" --depth=100 "$2" "$3" ;
    fi
}

### ostree
if [ "$PODMAN_BUILD_MODE" != "apt" ]; then
    if [ -e "$WORKING_DIR/ostree" ]; then
        rm -rf "$WORKING_DIR/ostree";
    fi
    git_clone_fetch $PODMAN_OSTREE_VERSION https://github.com/ostreedev/ostree "$WORKING_DIR/ostree" ;
    cd "$WORKING_DIR/ostree" ;
    git submodule update -f --init ;
    ./autogen.sh --prefix=$PODMAN_INSTALL_PREFIX --libdir=$PODMAN_INSTALL_PREFIX/lib64 --sysconfdir=$PODMAN_ETC_PREFIX ;
    sed -i '/.*--nonet.*/d' ./Makefile-man.am ;
    make -j ;
    sudo make install ;
fi

### golang
if [ ! -e "$PODMAN_INSTALL_PREFIX/$PODMAN_GOLANG_VERSION/go" ]; then
    sudo mkdir -p "$PODMAN_INSTALL_PREFIX/$PODMAN_GOLANG_VERSION" && sudo chmod 777 "$PODMAN_INSTALL_PREFIX/$PODMAN_GOLANG_VERSION";
    cd "$PODMAN_INSTALL_PREFIX/$PODMAN_GOLANG_VERSION";
    wget --no-check-certificate $PODMAN_GOLANG_URL -O "$PODMAN_GOLANG_BASENAME";
    tar -axvf "$PODMAN_GOLANG_BASENAME" ;
    for LINK_FILE in $(find "$PODMAN_INSTALL_PREFIX/$PODMAN_GOLANG_VERSION/go/bin" -name "*" -type f) ; do
        LINK_BASENAME="$(basename "$LINK_FILE")";
        if [ -e "$PODMAN_INSTALL_PREFIX/bin/$LINK_BASENAME" ]; then
            rm -f "$PODMAN_INSTALL_PREFIX/bin/$LINK_BASENAME";
        fi

        sudo ln -sf "$LINK_FILE" "$PODMAN_INSTALL_PREFIX/bin/$LINK_BASENAME";
    done
fi

### conmon
if [ -e "$WORKING_DIR/conmon" ]; then
    rm -rf "$WORKING_DIR/conmon";
fi
git_clone_fetch $PODMAN_CONMON_VERSION https://github.com/containers/conmon.git "$WORKING_DIR/conmon" ;
cd "$WORKING_DIR/conmon" ;
make -j PREFIX=$PODMAN_INSTALL_PREFIX ;
sudo make podman -j PREFIX=$PODMAN_INSTALL_PREFIX;

### runc
# if [ "$PODMAN_BUILD_MODE" != "apt" ]; then
    sudo mkdir -p "$GOPATH/src/github.com/opencontainers" && sudo chmod 777 "$GOPATH/src/github.com/opencontainers" ;
    if [ -e "$GOPATH/src/github.com/opencontainers/runc" ]; then
        rm -rf "$GOPATH/src/github.com/opencontainers/runc";
    fi
    git_clone_fetch $PODMAN_RUNC_VERSION https://github.com/opencontainers/runc.git "$GOPATH/src/github.com/opencontainers/runc" ;
    cd "$GOPATH/src/github.com/opencontainers/runc" ;
    make BUILDTAGS="selinux seccomp" -j PREFIX=$PODMAN_INSTALL_PREFIX ;
    sudo cp -f runc "$PODMAN_INSTALL_PREFIX/bin/runc" ;
# fi

### CNI plugins
# if [ "$PODMAN_BUILD_MODE" != "dnf" ] && [ "$PODMAN_BUILD_MODE" != "yum" ]; then
    sudo mkdir -p "$GOPATH/src/github.com/containernetworking" && sudo chmod 777 "$GOPATH/src/github.com/containernetworking";
    if [ -e "$GOPATH/src/github.com/containernetworking/plugins" ]; then
        rm -rf "$GOPATH/src/github.com/containernetworking/plugins";
    fi
    git_clone_fetch $PODMAN_CNI_PLUGINS_VERSION https://github.com/containernetworking/plugins.git "$GOPATH/src/github.com/containernetworking/plugins" ;
    cd "$GOPATH/src/github.com/containernetworking/plugins" ;
    ./build_linux.sh ;
    sudo mkdir -p "$PODMAN_INSTALL_PREFIX/libexec/cni" && sudo chmod 777 "$PODMAN_INSTALL_PREFIX/libexec/cni";
    sudo cp bin/* "$PODMAN_INSTALL_PREFIX/libexec/cni" ;
    
    ### Setup CNI networking
    sudo mkdir -p "$PODMAN_ETC_PREFIX/cni/net.d" && sudo chmod 777 "$PODMAN_ETC_PREFIX/cni/net.d";
    # curl -qsSL https://raw.githubusercontent.com/containers/libpod/master/cni/87-podman-bridge.conflist | sudo tee $PODMAN_ETC_PREFIX/cni/net.d/99-loopback.conf ;
# fi

### Add configuration
sudo mkdir -p "$PODMAN_ETC_PREFIX/containers" && sudo chmod 777 "$PODMAN_ETC_PREFIX/containers" ;
sudo curl -qsSL https://raw.githubusercontent.com/projectatomic/registries/master/registries.fedora -o $PODMAN_ETC_PREFIX/containers/registries.conf ;
sudo curl -qsSL https://raw.githubusercontent.com/containers/skopeo/master/default-policy.json -o $PODMAN_ETC_PREFIX/containers/policy.json ;

### Optional packages
### libpod
sudo mkdir -p "$GOPATH/src/github.com/containers" && sudo chmod 777 "$GOPATH/src/github.com/containers" ;
if [ -e "$GOPATH/src/github.com/containers/libpod" ]; then
    rm -rf "$GOPATH/src/github.com/containers/libpod";
fi
git_clone_fetch $PODMAN_LIBPOD_VERSION https://github.com/containers/libpod/ $GOPATH/src/github.com/containers/libpod ;
cd $GOPATH/src/github.com/containers/libpod ;
make BUILDTAGS="selinux seccomp systemd" PREFIX=$PODMAN_INSTALL_PREFIX ;
sudo make install PREFIX=$PODMAN_INSTALL_PREFIX ;

#### Build Tags
#### https://podman.io/getting-started/installation#build-tags

### Configuration files
sudo mkdir -p "/usr/share/containers" ;
sudo curl -qsSL https://src.fedoraproject.org/rpms/skopeo/raw/master/f/registries.conf -o $PODMAN_ETC_PREFIX/containers/registries.conf
echo "/usr/share/rhel/secrets:/run/secrets" | sudo tee "/usr/share/containers/mounts.conf" ;
sudo curl -qsSL https://src.fedoraproject.org/rpms/skopeo/raw/master/f/seccomp.json -o /usr/share/containers/seccomp.json ;
sudo curl -qsSL https://raw.githubusercontent.com/containers/skopeo/master/default-policy.json -o "$PODMAN_ETC_PREFIX/containers/policy.json" ;

### Configure maually'
echo "Add $PODMAN_INSTALL_PREFIX:$PODMAN_INSTALL_PREFIX/libexec to PATH in conmon_env_vars." ;
echo "Add $PODMAN_INSTALL_PREFIX/libexec/podman/conmon into conmon_path" ;
echo "Add $PODMAN_INSTALL_PREFIX/libexec/cni into cni_plugin_dir" ;
echo "Add $PODMAN_INSTALL_PREFIX/bin/runc into runc" ;
 
echo "vim $GOPATH/src/github.com/containers/libpod/libpod.conf
# add conmon_path
" ;

sudo mkdir -p "/usr/local/libexec"; 
sudo mkdir -p "/usr/local/bin"; 
for LIBEXEC_LINK in $PODMAN_INSTALL_PREFIX/libexec/* ; do
    LIBEXEC_LINK_BASENAME=$(basename $LIBEXEC_LINK);
    if [ -e "/usr/local/libexec/$LIBEXEC_LINK_BASENAME" ]; then
        if [ -e "/usr/local/libexec/$LIBEXEC_LINK_BASENAME.bak" ]; then
            sudo rm -rf "/usr/local/libexec/$LIBEXEC_LINK_BASENAME.bak";
        fi

        sudo mv "/usr/local/libexec/$LIBEXEC_LINK_BASENAME" "/usr/local/libexec/$LIBEXEC_LINK_BASENAME.bak";
    fi
    sudo ln -s "$LIBEXEC_LINK" "/usr/local/libexec/$LIBEXEC_LINK_BASENAME" ;

    if [ -e "/usr/local/lib/$LIBEXEC_LINK_BASENAME" ]; then
        if [ -e "/usr/local/lib/$LIBEXEC_LINK_BASENAME.bak" ]; then
            sudo rm -rf "/usr/local/lib/$LIBEXEC_LINK_BASENAME.bak";
        fi

        sudo mv "/usr/local/lib/$LIBEXEC_LINK_BASENAME" "/usr/local/lib/$LIBEXEC_LINK_BASENAME.bak";
    fi
    sudo ln -s "$LIBEXEC_LINK" "/usr/local/lib/$LIBEXEC_LINK_BASENAME" ;
done

for BIN_LINK in $PODMAN_INSTALL_PREFIX/bin/* ; do
    BIN_LINK_BASENAME=$(basename $BIN_LINK);
    if [ -e "/usr/local/bin/$BIN_LINK_BASENAME" ]; then
        if [ -e "/usr/local/bin/$BIN_LINK_BASENAME.bak" ]; then
            sudo rm -rf "/usr/local/bin/$BIN_LINK_BASENAME.bak";
        fi

        sudo mv "/usr/local/bin/$BIN_LINK_BASENAME" "/usr/local/bin/$BIN_LINK_BASENAME.bak";
    fi
    sudo ln -s "$BIN_LINK" "/usr/local/bin/$BIN_LINK_BASENAME" ;
done

# sudo podman network create ;
# Run script below if 'unable to start container "v2ray": container create failed (no logs from conmon): EOF'
# sudo rm /var/lib/containers/storage/overlay-containers/<CONTAINER ID>/userdata/winsz
