#!/bin/bash

mkdir -p $SETUP_INSTALL_PREFIX/gcc ;
cd $SETUP_INSTALL_PREFIX/gcc ;

GCC_INSTALLER_URL=https://github.com/owent-utils/bash-shell/raw/master/GCC%20Installer/gcc-10/installer.sh ;

wget $GCC_INSTALLER_URL ;

chmod +x *.sh ;

GCC_VERSION=$(./installer.sh -n);

export PATH=$SETUP_INSTALL_PREFIX/bin:$PATH

./installer.sh -p $SETUP_INSTALL_PREFIX/gcc/$GCC_VERSION ;

if [ -e $SETUP_INSTALL_PREFIX/gcc/latest ]; then
    rm -f $SETUP_INSTALL_PREFIX/gcc/latest ;
fi
ln -rs $SETUP_INSTALL_PREFIX/gcc/$GCC_VERSION $SETUP_INSTALL_PREFIX/gcc/latest ;
