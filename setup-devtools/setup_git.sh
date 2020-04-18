#!/bin/bash

mkdir -p $SETUP_INSTALL_PREFIX/git ;
cd $SETUP_INSTALL_PREFIX/git ;

RE2C_VERSION=1.2.1 ;
GIT_VERSION=2.25.1 ;
GIT_LFS_VERSION=2.10.0 ;
export PATH="$SETUP_INSTALL_PREFIX/bin:$PATH"

wget https://github.com/skvadrik/re2c/releases/download/$RE2C_VERSION/re2c-$RE2C_VERSION.tar.xz;
tar -axvf re2c-$RE2C_VERSION.tar.xz ;
cd re2c-$RE2C_VERSION ;
./configure --prefix=$SETUP_INSTALL_PREFIX/re2c/$RE2C_VERSION --with-pic=yes;
make -j8;
make install;


for UPDATE_LNK in $SETUP_INSTALL_PREFIX/re2c/$RE2C_VERSION/bin/*; do
    UNDATE_LNK_BASENAME="$(basename "$UPDATE_LNK")";
    if [ -e "$SETUP_INSTALL_PREFIX/bin/$UNDATE_LNK_BASENAME" ]; then
        rm -rf "$SETUP_INSTALL_PREFIX/bin/$UNDATE_LNK_BASENAME";
    fi
    ln -sf "$UPDATE_LNK" "$SETUP_INSTALL_PREFIX/bin/$UNDATE_LNK_BASENAME" ;
done

cd ..;

wget https://mirrors.edge.kernel.org/pub/software/scm/git/git-$GIT_VERSION.tar.xz;
tar -axvf git-$GIT_VERSION.tar.xz ;
cd git-$GIT_VERSION;
./configure --prefix=$SETUP_INSTALL_PREFIX/git/$GIT_VERSION --with-curl --with-expat --with-openssl --with-libpcre2 --with-editor=vim ;
make -j8 all doc;
make install install-doc install-html;
cd contrib/subtree;
make install install-doc install-html;


for UPDATE_LNK in $SETUP_INSTALL_PREFIX/git/$GIT_VERSION/bin/*; do
    UNDATE_LNK_BASENAME="$(basename "$UPDATE_LNK")";
    if [ -e "$SETUP_INSTALL_PREFIX/bin/$UNDATE_LNK_BASENAME" ]; then
        rm -rf "$SETUP_INSTALL_PREFIX/bin/$UNDATE_LNK_BASENAME";
    fi
    ln -sf "$UPDATE_LNK" "$SETUP_INSTALL_PREFIX/bin/$UNDATE_LNK_BASENAME" ;
done
cd ../../../ ;
mkdir -p git-lfs;
cd git-lfs;

# git lfs
wget https://github.com/git-lfs/git-lfs/releases/download/v$GIT_LFS_VERSION/git-lfs-linux-amd64-v$GIT_LFS_VERSION.tar.gz ;
mkdir git-lfs-v$GIT_LFS_VERSION;
cd git-lfs-v$GIT_LFS_VERSION ; 
tar -axvf ../git-lfs-linux-amd64-v$GIT_LFS_VERSION.tar.gz ;
env PREFIX=$SETUP_INSTALL_PREFIX/git-lfs/v$GIT_LFS_VERSION ./install.sh ;

for UPDATE_LNK in $SETUP_INSTALL_PREFIX/git-lfs/v$GIT_LFS_VERSION/bin/*; do
    UNDATE_LNK_BASENAME="$(basename "$UPDATE_LNK")";
    if [ -e "$SETUP_INSTALL_PREFIX/bin/$UNDATE_LNK_BASENAME" ]; then
        rm -rf "$SETUP_INSTALL_PREFIX/bin/$UNDATE_LNK_BASENAME";
    fi
    ln -sf "$UPDATE_LNK" "$SETUP_INSTALL_PREFIX/bin/$UNDATE_LNK_BASENAME" ;
done

cd ../../ ;
