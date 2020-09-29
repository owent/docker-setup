#!/bin/bash

NODEJS_VERSION=12.18.4

mkdir -p $SETUP_INSTALL_PREFIX/nodejs ;
cd $SETUP_INSTALL_PREFIX/nodejs ;


wget https://nodejs.org/dist/v$NODEJS_VERSION/node-v$NODEJS_VERSION-linux-x64.tar.xz ;
tar -axvf node-v$NODEJS_VERSION-linux-x64.tar.xz ;
mkdir $SETUP_INSTALL_PREFIX/nodejs ;
mv node-v$NODEJS_VERSION-linux-x64 $SETUP_INSTALL_PREFIX/nodejs/ ;

for UPDATE_LNK in $SETUP_INSTALL_PREFIX/nodejs/node-v$NODEJS_VERSION-linux-x64/bin/*; do
    UNDATE_LNK_BASENAME="$(basename "$UPDATE_LNK")";
    if [ -e "$SETUP_INSTALL_PREFIX/bin/$UNDATE_LNK_BASENAME" ]; then
        rm -rf "$SETUP_INSTALL_PREFIX/bin/$UNDATE_LNK_BASENAME";
    fi
    ln -sf "$UPDATE_LNK" "$SETUP_INSTALL_PREFIX/bin/$UNDATE_LNK_BASENAME" ;
done

# init
export PATH=$SETUP_INSTALL_PREFIX/bin:$PATH

npm config set registry https://mirrors.tencent.com/npm/ ;

npm install -g yarn ;
