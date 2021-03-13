#!/bin/bash

mkdir -p $SETUP_INSTALL_PREFIX/llvm ;
cd $SETUP_INSTALL_PREFIX/llvm ;

LLVM_INSTALLER_URL=https://github.com/owent-utils/bash-shell/raw/master/LLVM%26Clang%20Installer/10.0/installer.sh ;

wget $LLVM_INSTALLER_URL ;

chmod +x *.sh ;

LLVM_VERSION=$(./installer.sh -n);

export PATH=$SETUP_INSTALL_PREFIX/bin:$PATH

source $SETUP_INSTALL_PREFIX/gcc/latest/load-gcc-envs.sh ;

./installer.sh -p $SETUP_INSTALL_PREFIX/llvm/$LLVM_VERSION ;

if [ -e $SETUP_INSTALL_PREFIX/llvm/latest ]; then
    rm -f $SETUP_INSTALL_PREFIX/llvm/latest ;
fi

ln -rs $SETUP_INSTALL_PREFIX/llvm/$LLVM_VERSION $SETUP_INSTALL_PREFIX/llvm/latest ;
