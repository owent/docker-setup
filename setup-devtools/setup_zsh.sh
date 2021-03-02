#!/bin/bash

ZSH_VERSION=5.8 ;

if [[ -z "$SETUP_INSTALL_PREFIX" ]]; then
    SETUP_INSTALL_PREFIX=/opt
fi

mkdir -p $SETUP_INSTALL_PREFIX/zsh ;
cd $SETUP_INSTALL_PREFIX/zsh ;

wget https://nchc.dl.sourceforge.net/project/zsh/zsh/$ZSH_VERSION/zsh-$ZSH_VERSION.tar.xz ;

tar -axvf zsh-$ZSH_VERSION.tar.xz ;
cd zsh-$ZSH_VERSION ;
./configure --prefix=$SETUP_INSTALL_PREFIX/zsh/$ZSH_VERSION --enable-cap --enable-pcre --enable-multibyte --enable-unicode9 --with-tcsetpgrp ;
make -j8 ;
make install ;
cd .. ;

for UPDATE_LNK in $SETUP_INSTALL_PREFIX/zsh/$ZSH_VERSION/bin/*; do
    UNDATE_LNK_BASENAME="$(basename "$UPDATE_LNK")";
    if [ -e "$SETUP_INSTALL_PREFIX/bin/$UNDATE_LNK_BASENAME" ]; then
        rm -rf "$SETUP_INSTALL_PREFIX/bin/$UNDATE_LNK_BASENAME";
    fi
    ln -sf "$UPDATE_LNK" "$SETUP_INSTALL_PREFIX/bin/$UNDATE_LNK_BASENAME" ;
done
