#!/bin/bash

CMAKE_VERSION=3.16.5 ;

mkdir -p $SETUP_INSTALL_PREFIX/cmake ;
cd $SETUP_INSTALL_PREFIX/cmake ;

wget https://github.com/Kitware/CMake/releases/download/v$CMAKE_VERSION/cmake-$CMAKE_VERSION-Linux-x86_64.sh ;

mkdir -p $SETUP_INSTALL_PREFIX/cmake/$CMAKE_VERSION ;

chmod +x ./cmake-$CMAKE_VERSION-Linux-x86_64.sh ;

./cmake-$CMAKE_VERSION-Linux-x86_64.sh --prefix=$SETUP_INSTALL_PREFIX/cmake/$CMAKE_VERSION --skip-license ;

if [ -e $SETUP_INSTALL_PREFIX/cmake/latest ]; then
    rm -f $SETUP_INSTALL_PREFIX/cmake/latest ;
fi
ln -s $SETUP_INSTALL_PREFIX/cmake/$CMAKE_VERSION $SETUP_INSTALL_PREFIX/cmake/latest ;

for UPDATE_LNK in $SETUP_INSTALL_PREFIX/cmake/$CMAKE_VERSION/bin/*; do
    UNDATE_LNK_BASENAME="$(basename "$UPDATE_LNK")";
    if [ -e "$SETUP_INSTALL_PREFIX/bin/$UNDATE_LNK_BASENAME" ]; then
        rm -rf "$SETUP_INSTALL_PREFIX/bin/$UNDATE_LNK_BASENAME";
    fi
    ln -sf "$UPDATE_LNK" "$SETUP_INSTALL_PREFIX/bin/$UNDATE_LNK_BASENAME" ;
done