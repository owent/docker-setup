#!/bin/bash

WORKING_DIR="$PWD";
export PATH="$PATH:/sbin" ;

grep -E -i "ubuntu|debian" /etc/os-release ;

if [ $? -eq 0 ]; then
    # Dependencies for Debian, Ubuntu, and related distributions
    sudo apt install -y btrfs-tools git golang-go go-md2man iptables libassuan-dev libc6-dev libdevmapper-dev libglib2.0-dev libgpgme-dev libgpg-error-dev libostree-dev libprotobuf-dev libprotobuf-c-dev libseccomp-dev libselinux1-dev libsystemd-dev pkg-config runc uidmap
    sudo apt install -y make automake bison e2fsprogs e2fslibs-dev fuse libfuse-dev libgpgme-dev liblzma-dev libtool zlib1g libapparmor-dev libcap-dev
    apt info libfuse3-dev > /dev/null 2>&1 ;
    if [ $! -eq 0 ]; then
        sudo apt install -y libfuse3-dev;
    fi
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
    sudo $PODMAN_BUILD_MODE install -y automake bison e2fsprogs-devel fuse-devel libtool xz-devel zlib-devel libbtrfs-dev libcap-devel # fuse-overlayfs
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
PODMAN_CNI_PLUGINS_VERSION=v0.8.3 ; # For rootful network
PODMAN_LIBPOD_VERSION=v1.6.4 ;
PODMAN_SLIRP4NETNS_VERSION=v0.4.3 ; # For rootless network
PODMAN_FUSE_OVERLAYFS=v0.7.2 ;
PODMAN_FUSE_OVERLAYFS_OVERWRITE=0 ;

PODMAN_GOLANG_BASENAME=$(basename $PODMAN_GOLANG_URL);
PODMAN_GOLANG_VERSION=$(echo "$PODMAN_GOLANG_BASENAME" | awk '{if(match($0, /go[0-9]*\.[0-9]*(\.[0-9]*)/, m)) {print m[0];}}') ;
sudo mkdir -p "$PODMAN_INSTALL_PREFIX/bin" && sudo chmod 755 "$PODMAN_INSTALL_PREFIX/bin";
export PATH="$PODMAN_INSTALL_PREFIX/bin:$PATH";
export GOPATH="$PODMAN_INSTALL_PREFIX/GOPATH";
export GOPROXY=https://goproxy.cn,direct ;
# export GOPROXY=https://mirrors.aliyun.com/goproxy/ ;
# export GOPROXY=http://mirrors.cloud.tencent.com/go/ ;
export GOPRIVATE=github.com ;
sudo mkdir -p "$GOPATH" && sudo chmod 755 "$GOPATH" ;

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
    sudo mkdir -p "$PODMAN_INSTALL_PREFIX/$PODMAN_GOLANG_VERSION" && sudo chmod 755 "$PODMAN_INSTALL_PREFIX/$PODMAN_GOLANG_VERSION";
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
git_clone_fetch $PODMAN_CONMON_VERSION https://github.com/containers/conmon.git "$WORKING_DIR/conmon" ;
cd "$WORKING_DIR/conmon" ;
make -j PREFIX=$PODMAN_INSTALL_PREFIX ;
sudo make podman -j PREFIX=$PODMAN_INSTALL_PREFIX;

### runc
# if [ "$PODMAN_BUILD_MODE" != "apt" ]; then
    sudo mkdir -p "$GOPATH/src/github.com/opencontainers" && sudo chmod 755 "$GOPATH/src/github.com/opencontainers" ;
    git_clone_fetch $PODMAN_RUNC_VERSION https://github.com/opencontainers/runc.git "$GOPATH/src/github.com/opencontainers/runc" ;
    cd "$GOPATH/src/github.com/opencontainers/runc" ;
    make BUILDTAGS="selinux seccomp" -j PREFIX=$PODMAN_INSTALL_PREFIX ;
    sudo cp -f runc "$PODMAN_INSTALL_PREFIX/bin/runc" ;
# fi

### CNI plugins
# if [ "$PODMAN_BUILD_MODE" != "dnf" ] && [ "$PODMAN_BUILD_MODE" != "yum" ]; then
    sudo mkdir -p "$GOPATH/src/github.com/containernetworking" && sudo chmod 755 "$GOPATH/src/github.com/containernetworking";
    git_clone_fetch $PODMAN_CNI_PLUGINS_VERSION https://github.com/containernetworking/plugins.git "$GOPATH/src/github.com/containernetworking/plugins" ;
    cd "$GOPATH/src/github.com/containernetworking/plugins" ;
    ./build_linux.sh ;
    sudo mkdir -p "$PODMAN_INSTALL_PREFIX/libexec/cni" && sudo chmod 755 "$PODMAN_INSTALL_PREFIX/libexec/cni";
    sudo cp bin/* "$PODMAN_INSTALL_PREFIX/libexec/cni" ;
    
    ### Setup CNI networking
    sudo mkdir -p "$PODMAN_ETC_PREFIX/cni/net.d" && sudo chmod 755 "$PODMAN_ETC_PREFIX/cni/net.d";
    # curl -qsSL https://raw.githubusercontent.com/containers/libpod/master/cni/87-podman-bridge.conflist | sudo tee $PODMAN_ETC_PREFIX/cni/net.d/99-loopback.conf ;
# fi

### Add configuration
sudo mkdir -p "$PODMAN_ETC_PREFIX/containers" && sudo chmod 755 "$PODMAN_ETC_PREFIX/containers" ;
sudo curl -qsSL https://raw.githubusercontent.com/projectatomic/registries/master/registries.fedora -o $PODMAN_ETC_PREFIX/containers/registries.conf ;
sudo curl -qsSL https://raw.githubusercontent.com/containers/skopeo/master/default-policy.json -o $PODMAN_ETC_PREFIX/containers/policy.json ;

### Optional packages
### libpod
sudo mkdir -p "$GOPATH/src/github.com/containers" && sudo chmod 755 "$GOPATH/src/github.com/containers" ;
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

#### Build fuse-overlayfs
#### https://github.com/containers/fuse-overlayfs.git
if [ ! -e "/usr/bin/fuse-overlayfs" ] || [ $PODMAN_FUSE_OVERLAYFS_OVERWRITE -ne 0 ]; then
    git_clone_fetch $PODMAN_FUSE_OVERLAYFS https://github.com/containers/fuse-overlayfs.git "$WORKING_DIR/fuse-overlayfs" ;
    cd "$WORKING_DIR/fuse-overlayfs" ;
    sh autogen.sh ;
    LIBS="-ldl" LDFLAGS="-static" ./configure --prefix /usr ;
    make -j ;
    sudo cp fuse-overlayfs "/usr/bin/fuse-overlayfs" ;
fi

#### Build slirp4netns
which slirp4netns > /dev/null 2>&1 ;
if [ $? -ne 0 ]; then
    git_clone_fetch $PODMAN_SLIRP4NETNS_VERSION https://github.com/rootless-containers/slirp4netns.git "$WORKING_DIR/slirp4netns" ;
    cd "$WORKING_DIR/slirp4netns" ;
    sh autogen.sh ;
    LIBS="-ldl" LDFLAGS="-static" ./configure --prefix $PODMAN_INSTALL_PREFIX ;
    make -j ;
    make install ;
    sudo cp slirp4netns "/usr/bin/slirp4netns" ;
fi

### Configure maually'
EDIT_LIBPOD_CONF="$GOPATH/src/github.com/containers/libpod/libpod.conf";
echo -e "\033[1;31mvim $EDIT_LIBPOD_CONF\033[0;m" ;
echo -e "\033[1;32mAdd $PODMAN_INSTALL_PREFIX/bin:$PODMAN_INSTALL_PREFIX/libexec to PATH in conmon_env_vars.\033[0;m" ;
echo -e "\033[1;32mAdd $PODMAN_INSTALL_PREFIX/libexec/podman/conmon into conmon_path\033[0;m" ;
echo -e "\033[1;32mAdd $PODMAN_INSTALL_PREFIX/libexec/cni into cni_plugin_dir\033[0;m" ;
echo -e "\033[1;32mAdd $PODMAN_INSTALL_PREFIX/bin/runc into runc\033[0;m" ;

sed -i -r "s#PATH=([^\"]+)#PATH=$PODMAN_INSTALL_PREFIX/bin:$PODMAN_INSTALL_PREFIX/libexec:\\1#" $EDIT_LIBPOD_CONF ;
REGEX_RULE="$PODMAN_INSTALL_PREFIX/libexec/podman/conmon";
sed -i -r "/${REGEX_RULE//\//\\\/}/d" $EDIT_LIBPOD_CONF ;
sed -i -r "/conmon_path\\s*=\\s*\\[/a        \"$REGEX_RULE\"," $EDIT_LIBPOD_CONF ;
REGEX_RULE="$PODMAN_INSTALL_PREFIX/libexec/cni" ;
sed -i -r "/${REGEX_RULE//\//\\\/}/d" $EDIT_LIBPOD_CONF ;
sed -i -r "/cni_plugin_dir\\s*=\\s*\\[/a        \"$REGEX_RULE\"," $EDIT_LIBPOD_CONF ;
REGEX_RULE="$PODMAN_INSTALL_PREFIX/bin/runc" ;
sed -i -r "/${REGEX_RULE//\//\\\/}/d" $EDIT_LIBPOD_CONF ;
sed -i -r "/runc\\s*=\\s*\\[/a        \"$REGEX_RULE\"," $EDIT_LIBPOD_CONF ;

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

if [ $(sudo podman network ls -q | wc | awk '{print $1}') -eq 0 ]; then
    sudo podman network create ;
fi

echo -e "You can use script below to start rootful container:\n\033[32msudo podman run [options...] \033[1;31m--network $(sudo podman network ls -q)\033[1;32m IMAGE [CMD/ARGS...]\033[0;m"

# Run script below if 'unable to start container "v2ray": container create failed (no logs from conmon): EOF'
# sudo rm /var/lib/containers/storage/overlay-containers/<CONTAINER ID>/userdata/winsz
