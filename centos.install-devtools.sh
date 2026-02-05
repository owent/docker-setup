#!/bin/bash

if [ "x$SETUP_INSTALL_PREFIX" == "x" ]; then
    export SETUP_INSTALL_PREFIX=/opt
fi

if [ "x$SETUP_WORK_DIR" == "x" ]; then
    export SETUP_WORK_DIR=/data/setup
fi

cd "$(dirname $0)"

cat /etc/os-release ;

CURRENT_SCRIPT_DIR=$PWD;

chmod +x $CURRENT_SCRIPT_DIR/setup/*.sh 
chmod +x $CURRENT_SCRIPT_DIR/*.sh ;

dnf install -y libtool m4 autoconf python3 python3-setuptools python3-pip python3-devel info asciidoc xmlto zlib-devel chrpath;
dnf install -y ca-certificates gcc gcc-c++ gdb valgrind automake autoconf m4 make libcurl-devel expat expat-devel glibc glibc-devel;
dnf install -y pkgconf-pkg-config java-latest-openjdk

export SETUP_INSTALL_PKGTOOL_CENTOS=dnf
export SETUP_INSTALL_DISTRIBUTION_CENTOS=8


# $CURRENT_SCRIPT_DIR/setup/setup_dotnetcore.sh
# $CURRENT_SCRIPT_DIR/setup/setup_p4.sh

$CURRENT_SCRIPT_DIR/setup/setup_devnet_profile.sh
if [ "x" != "$SETUP_INSTALL_PROXY" ]; then
    export http_proxy=$SETUP_INSTALL_PROXY
    export https_proxy=$http_proxy
    export ftp_proxy=$http_proxy
    export rsync_proxy=$http_proxy
    if [ "x" != "$SETUP_INSTALL_NO_PROXY" ]; then
        export no_proxy=$SETUP_INSTALL_NO_PROXY
    fi
fi

$CURRENT_SCRIPT_DIR/setup/setup_git.sh
$CURRENT_SCRIPT_DIR/setup/setup_golang.sh
$CURRENT_SCRIPT_DIR/setup/setup_nodejs.sh
$CURRENT_SCRIPT_DIR/setup/setup_ninja.sh
$CURRENT_SCRIPT_DIR/setup/setup_cmake.sh
$CURRENT_SCRIPT_DIR/setup/setup_tmux.sh
$CURRENT_SCRIPT_DIR/setup/setup_zsh.sh

$CURRENT_SCRIPT_DIR/setup/setup_gcc.sh
$CURRENT_SCRIPT_DIR/setup/setup_llvm.sh

# setup sshd
./setup.sshd.sh
