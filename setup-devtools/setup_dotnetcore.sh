#!/bin/bash

# @see https://dotnet.microsoft.com/download/dotnet-core for more details
DOTNET_CORE_VERSIONS=(2.1 3.1) ; # all LTS versions with support

mkdir -p $SETUP_INSTALL_PREFIX/dotnet ;

cd $SETUP_INSTALL_PREFIX/dotnet ;

function run_wget() {
    if [ "x" != "$SETUP_INSTALL_PROXY" ]; then
        env http_proxy=$SETUP_INSTALL_PROXY https_proxy=$SETUP_INSTALL_PROXY wget "$@";
    else
        wget "$@";
    fi
}

# setup dotnet
if [ "x" != "x$SETUP_INSTALL_DISTRIBUTION_CENTOS" ]; then
    run_wget https://packages.microsoft.com/config/centos/$SETUP_INSTALL_DISTRIBUTION_CENTOS/packages-microsoft-prod.rpm ;
    rpm -Uvh packages-microsoft-prod.rpm ;
    sed -i 's/gpgcheck=1/gpgcheck=0/g' /etc/yum.repos.d/microsoft-prod.repo ;
    sed -i 's/sslverify=1/sslverify=0/g' /etc/yum.repos.d/microsoft-prod.repo ;
    if [ "x" != "$SETUP_INSTALL_PROXY" ]; then
        sed -i '/proxy=/d' /etc/yum.repos.d/microsoft-prod.repo ;
        echo "proxy=$SETUP_INSTALL_PROXY" >> /etc/yum.repos.d/microsoft-prod.repo
    fi

    for DOTNET_CORE_VERSION in $DOTNET_CORE_VERSIONS; do
        $SETUP_INSTALL_PKGTOOL_CENTOS install -y dotnet-sdk-$DOTNET_CORE_VERSION dotnet-runtime-$DOTNET_CORE_VERSION ;
    done

    # install powershell
    $SETUP_INSTALL_PKGTOOL_CENTOS install -y powershell ;

elif [ "x" != "x$SETUP_INSTALL_DISTRIBUTION_UBUNTU" ]; then
    run_wget -q https://packages.microsoft.com/config/ubuntu/$SETUP_INSTALL_DISTRIBUTION_UBUNTU/packages-microsoft-prod.deb -O packages-microsoft-prod.deb ;
    dpkg -i packages-microsoft-prod.deb ;
    add-apt-repository universe ;
    apt update -y ;
    apt install -y apt-transport-https ;
    apt update -y ;

    for DOTNET_CORE_VERSION in $DOTNET_CORE_VERSIONS; do
        $SETUP_INSTALL_PKGTOOL_CENTOS install -y dotnet-sdk-$DOTNET_CORE_VERSION dotnet-runtime-$DOTNET_CORE_VERSION ;
    done

    # install powershell
    apt show powershell > /dev/null 2>&1 ;
    if [ $? -eq 0 ]; then
        apt install -y powershell ;
    else
        apt install -y powershell-preview ;
    fi

elif [ "x" != "x$SETUP_INSTALL_DISTRIBUTION_DEBIAN" ]; then
    run_wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > /etc/apt/trusted.gpg.d/microsoft.asc.gpg ;
    run_wget https://packages.microsoft.com/config/debian/$SETUP_INSTALL_DISTRIBUTION_DEBIAN/prod.list -O /etc/apt/sources.list.d/microsoft-prod.list ;
    chown root:root /etc/apt/trusted.gpg.d/microsoft.asc.gpg ;
    chown root:root /etc/apt/sources.list.d/microsoft-prod.list ;

    apt update -y ;
    apt install -y apt-transport-https libgssapi-krb5-2 liburcu6 ;
    apt update -y ;

    for DOTNET_CORE_VERSION in $DOTNET_CORE_VERSIONS; do
        $SETUP_INSTALL_PKGTOOL_CENTOS install -y dotnet-sdk-$DOTNET_CORE_VERSION dotnet-runtime-$DOTNET_CORE_VERSION ;
    done

    # install powershell
    apt show powershell > /dev/null 2>&1 ;
    if [ $? -eq 0 ]; then
        apt install -y powershell ;
    else
        apt install -y powershell-preview ;
    fi
fi
