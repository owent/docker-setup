#!/bin/bash

TMUX_PREBUILT_VERSION=3.1b ;

TMUX_PURL=https://github.com/owent-contrib/tmux-build-musl/releases/download/3.0a/tmux-3.0a.musl-bin.tar.gz ;

mkdir -p $SETUP_INSTALL_PREFIX/tmux ;
cd $SETUP_INSTALL_PREFIX/tmux ;

wget $TMUX_PURL ;

mkdir -p $SETUP_INSTALL_PREFIX/tmux/$TMUX_PREBUILT_VERSION ;
cd $SETUP_INSTALL_PREFIX/tmux/$TMUX_PREBUILT_VERSION ;
tar -axvf $SETUP_INSTALL_PREFIX/tmux/tmux-$TMUX_PREBUILT_VERSION.musl-bin.tar.gz ;
mv tmux/* ./;
rm -r tmux ;

for UPDATE_LNK in $SETUP_INSTALL_PREFIX/tmux/$TMUX_PREBUILT_VERSION/bin/*; do
    UNDATE_LNK_BASENAME="$(basename "$UPDATE_LNK")";
    if [ -e "$SETUP_INSTALL_PREFIX/bin/$UNDATE_LNK_BASENAME" ]; then
        rm -rf "$SETUP_INSTALL_PREFIX/bin/$UNDATE_LNK_BASENAME";
    fi
    ln -sf "$UPDATE_LNK" "$SETUP_INSTALL_PREFIX/bin/$UNDATE_LNK_BASENAME" ;
done
