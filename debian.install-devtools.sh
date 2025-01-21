#!/bin/bash

if [ "x$SETUP_INSTALL_PREFIX" == "x" ]; then
    export SETUP_INSTALL_PREFIX=/opt
fi

if [ "x$SETUP_WORK_DIR" == "x" ]; then
    export SETUP_WORK_DIR=/data/setup
fi

cd "$(dirname $0)"

cat /etc/os-release

CURRENT_SCRIPT_DIR=$PWD

chmod +x $CURRENT_SCRIPT_DIR/setup/*.sh
chmod +x $CURRENT_SCRIPT_DIR/*.sh

# Development tools
apt install -y systemd-coredump libssl-dev python3-setuptools python3-pip python3-mako perl automake gdb valgrind unzip lunzip \
    p7zip-full autoconf libtool build-essential pkg-config gettext asciidoc xmlto xmltoman expat libexpat1-dev m4 \
    libcurl4-openssl-dev libc6-dev re2c gettext zlib1g zlib1g-dev chrpath autoconf
apt install -y libc6-dev-x32 libpcre2-dev pcre2-utils make pkgconf expat libexpat1-dev ninja-build

export SETUP_INSTALL_DISTRIBUTION_DEBIAN=$(cat /etc/os-release | perl -n -e'/VERSION_ID="?([^"]+)"?/ && print $1')

# setup sshd
./setup.sshd.sh

$CURRENT_SCRIPT_DIR/setup/build-toolchain.sh
