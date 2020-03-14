#!/bin/bash

mkdir -p $SETUP_INSTALL_PREFIX/ninja-build ;
cd $SETUP_INSTALL_PREFIX/ninja-build ;

wget https://github.com/ninja-build/ninja/archive/v1.10.0.tar.gz ;
tar -axvf v1.10.0.tar.gz ;
cd ninja-1.10.0 ;

LDFLAGS="-static -static-libgcc -static-libstdc++" ./configure.py --bootstrap ;

mkdir -p $SETUP_INSTALL_PREFIX/ninja-build/latest/ ;

cp -f ninja $SETUP_INSTALL_PREFIX/ninja-build/latest/ ;

for UPDATE_LNK in $SETUP_INSTALL_PREFIX/ninja-build/latest/*; do
    UNDATE_LNK_BASENAME="$(basename "$UPDATE_LNK")";
    if [ -e "$SETUP_INSTALL_PREFIX/bin/$UNDATE_LNK_BASENAME" ]; then
        rm -rf "$SETUP_INSTALL_PREFIX/bin/$UNDATE_LNK_BASENAME";
    fi
    ln -sf "$UPDATE_LNK" "$SETUP_INSTALL_PREFIX/bin/$UNDATE_LNK_BASENAME" ;
done
