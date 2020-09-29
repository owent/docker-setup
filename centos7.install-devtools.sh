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

yum install -y libtool pkgconfig m4 autoconf python python-setuptools python-pip python-requests python-devel python3-rpm-macros python34 python34-setuptools ;
yum install -y texinfo asciidoc xmlto zlib-devel chrpath;
yum install -y ca-certificates gcc gcc-c++ gdb valgrind automake autoconf m4 make libcurl-devel expat expat-devel glibc glibc-devel;
yum install -y pkgconfig java-1.8.0-openjdk

export SETUP_INSTALL_PKGTOOL_CENTOS=yum
export SETUP_INSTALL_DISTRIBUTION_CENTOS=7

$CURRENT_SCRIPT_DIR/setup/setup_dotnetcore.sh
$CURRENT_SCRIPT_DIR/setup/setup_p4.sh

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

