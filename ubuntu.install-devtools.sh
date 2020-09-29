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

# Development tools
apt install -y systemd-coredump libssl-dev python3-setuptools python3-pip python3-mako perl automake gdb valgrind unzip lunzip  \
               p7zip-full autoconf libtool build-essential pkg-config gettext asciidoc xmlto xmltoman expat libexpat1-dev       \
               libcurl4-openssl-dev re2c gettext zlibc zlib1g zlib1g-dev default-jdk chrpath

export SETUP_INSTALL_DISTRIBUTION_UBUNTU=$(cat /etc/os-release | perl -n -e'/VERSION_ID="?([^"]+)"?/ && print $1') ;


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
