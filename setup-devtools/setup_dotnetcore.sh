#!/bin/bash

DOTNET_CORE_VERSION=3.0 ;
POWERSHELL_CORE_VERSION=6.2.3 ;

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
    POWERSHELL_CORE_URL=https://github.com/PowerShell/PowerShell/releases/download/v$POWERSHELL_CORE_VERSION/powershell-$POWERSHELL_CORE_VERSION-1.rhel.$SETUP_INSTALL_DISTRIBUTION_CENTOS.x86_64.rpm ;
    run_wget https://packages.microsoft.com/config/centos/$SETUP_INSTALL_DISTRIBUTION_CENTOS/packages-microsoft-prod.rpm ;
    rpm -Uvh packages-microsoft-prod.rpm ;
    sed -i 's/gpgcheck=1/gpgcheck=0/g' /etc/yum.repos.d/microsoft-prod.repo ;
    sed -i 's/sslverify=1/sslverify=0/g' /etc/yum.repos.d/microsoft-prod.repo ;
    if [ "x" != "$SETUP_INSTALL_PROXY" ]; then
        sed -i '/proxy=/d' /etc/yum.repos.d/microsoft-prod.repo ;
        echo "proxy=$SETUP_INSTALL_PROXY" >> /etc/yum.repos.d/microsoft-prod.repo
    fi

    $SETUP_INSTALL_PKGTOOL_CENTOS install -y dotnet-sdk-$DOTNET_CORE_VERSION dotnet-runtime-$DOTNET_CORE_VERSION dotnet-sdk-2.2 dotnet-runtime-2.2 ;

    # setup powershell

    run_wget ${POWERSHELL_CORE_URL} ;
    rpm -Uvh $(basename $POWERSHELL_CORE_URL);

elif [ "x" != "x$SETUP_INSTALL_DISTRIBUTION_UBUNTU" ]; then
    run_wget -q https://packages.microsoft.com/config/ubuntu/$SETUP_INSTALL_DISTRIBUTION_UBUNTU/packages-microsoft-prod.deb -O packages-microsoft-prod.deb ;
    dpkg -i packages-microsoft-prod.deb ;
    add-apt-repository universe ;
    apt update -y ;
    apt install -y apt-transport-https ;
    apt update -y ;
    apt install -y dotnet-sdk-$DOTNET_CORE_VERSION dotnet-runtime-$DOTNET_CORE_VERSION dotnet-sdk-2.2 dotnet-runtime-2.2 powershell ;
elif [ "x" != "x$SETUP_INSTALL_DISTRIBUTION_DEBIAN" ]; then
    POWERSHELL_CORE_URL=https://github.com/PowerShell/PowerShell/releases/download/v$POWERSHELL_CORE_VERSION/powershell-$POWERSHELL_CORE_VERSION-linux-x64.tar.gz ;

    run_wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > /etc/apt/trusted.gpg.d/microsoft.asc.gpg ;
    run_wget https://packages.microsoft.com/config/debian/10/prod.list -O /etc/apt/sources.list.d/microsoft-prod.list ;
    chown root:root /etc/apt/trusted.gpg.d/microsoft.asc.gpg ;
    chown root:root /etc/apt/sources.list.d/microsoft-prod.list ;

    apt update -y ;
    apt install -y apt-transport-https libgssapi-krb5-2 liburcu6 ;
    apt update -y ;
    apt install -y dotnet-sdk-$DOTNET_CORE_VERSION dotnet-runtime-$DOTNET_CORE_VERSION dotnet-sdk-2.2 dotnet-runtime-2.2 powershell ;

    run_wget $POWERSHELL_CORE_URL -O $(basename $POWERSHELL_CORE_URL) ;
    mkdir -p $SETUP_INSTALL_PREFIX/microsoft/powershell/$POWERSHELL_CORE_VERSION ;
    tar -axvf $(basename $POWERSHELL_CORE_URL) -C $SETUP_INSTALL_PREFIX/microsoft/powershell/$POWERSHELL_CORE_VERSION ;
    chmod +x $SETUP_INSTALL_PREFIX/microsoft/powershell/$POWERSHELL_CORE_VERSION/* ;
    ln -sf $SETUP_INSTALL_PREFIX/microsoft/powershell/$POWERSHELL_CORE_VERSION/pwsh /usr/bin/pwsh ;
fi
