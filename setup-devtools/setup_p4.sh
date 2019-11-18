#!/bin/bash

mkdir -p $SETUP_INSTALL_PREFIX/perforce ;

cd $SETUP_INSTALL_PREFIX/perforce ;

function run_wget() {
    if [ "x" != "$SETUP_INSTALL_PROXY" ]; then
        env http_proxy=$SETUP_INSTALL_PROXY https_proxy=$SETUP_INSTALL_PROXY wget "$@";
    else
        wget "$@";
    fi
}

if [ "x" != "x$SETUP_INSTALL_DISTRIBUTION_CENTOS" ]; then
    run_wget https://package.perforce.com/perforce.pubkey ;

    rpm --import perforce.pubkey ;

    echo "[perforce]
name=Perforce
baseurl=http://package.perforce.com/yum/rhel/$SETUP_INSTALL_DISTRIBUTION_CENTOS/x86_64
enabled=1
gpgcheck=1
" > /etc/yum.repos.d/perforce.repo ;

    if [ "x" != "$SETUP_INSTALL_PROXY" ]; then
        echo "proxy=$SETUP_INSTALL_PROXY" > /etc/yum.repos.d/perforce.repo ;
    fi

    $SETUP_INSTALL_PKGTOOL_CENTOS install -y helix-p4d ;
elif [ "x" != "x$SETUP_INSTALL_DISTRIBUTION_UBUNTU" ]; then
    run_wget -qO - https://package.perforce.com/perforce.pubkey | apt-key add - ;
    echo 'deb http://package.perforce.com/apt/ubuntu {distro} release' > /etc/apt/sources.list.d/perforce.list ;
    apt update -y ;
    apt install -y helix-p4d ;
elif [ "x" != "x$SETUP_INSTALL_DISTRIBUTION_DEBIAN" ]; then
    run_wget -qO - https://package.perforce.com/perforce.pubkey | apt-key add - ;
    echo 'deb http://package.perforce.com/apt/debian {distro} release' > /etc/apt/sources.list.d/perforce.list ;
    apt update -y ;
    apt install -y helix-p4d ;
fi