#!/bin/bash

GOLANG_VERSION=1.15.2;

mkdir -p $SETUP_INSTALL_PREFIX/golang ;
cd $SETUP_INSTALL_PREFIX/golang ;

wget https://dl.google.com/go/go$GOLANG_VERSION.linux-amd64.tar.gz ;

tar -axvf go$GOLANG_VERSION.linux-amd64.tar.gz ;

mkdir -p $SETUP_INSTALL_PREFIX/golang ;

if [ -e $SETUP_INSTALL_PREFIX/golang/$GOLANG_VERSION ]; then
    rm -rf $SETUP_INSTALL_PREFIX/golang/$GOLANG_VERSION;
fi

mv go $SETUP_INSTALL_PREFIX/golang/$GOLANG_VERSION ;

for UPDATE_LNK in $SETUP_INSTALL_PREFIX/golang/$GOLANG_VERSION/bin/*; do
    UNDATE_LNK_BASENAME="$(basename "$UPDATE_LNK")";
    if [ -e "$SETUP_INSTALL_PREFIX/bin/$UNDATE_LNK_BASENAME" ]; then
        rm -rf "$SETUP_INSTALL_PREFIX/bin/$UNDATE_LNK_BASENAME";
    fi
    ln -rsf "$UPDATE_LNK" "$SETUP_INSTALL_PREFIX/bin/$UNDATE_LNK_BASENAME" ;
done

