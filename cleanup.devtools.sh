#!/bin/bash

if [ "x$SETUP_INSTALL_PREFIX" == "x" ]; then
    export SETUP_INSTALL_PREFIX=/opt
fi

if [ "x$SETUP_WORK_DIR" == "x" ]; then
    export SETUP_WORK_DIR=/data/setup
fi

if [ -e "$SETUP_WORK_DIR/server-docker/.git" ]; then
    export PATH=$SETUP_INSTALL_PREFIX/bin:$PATH
    if [ -e "$SETUP_INSTALL_PREFIX/server-docker" ]; then
        rm -rf "$SETUP_INSTALL_PREFIX/server-docker" ;
    fi

    mkdir -p $SETUP_INSTALL_PREFIX/server-docker;
    cd "$SETUP_WORK_DIR/server-docker" ;
    echo "======================== Git Repo Remote ========================" > $SETUP_INSTALL_PREFIX/server-docker/git-repo.txt ;
    git remote show $(git remote) -n >> $SETUP_INSTALL_PREFIX/server-docker/git-repo.txt ;
    echo "======================== Git Repo Commit ========================" >> $SETUP_INSTALL_PREFIX/server-docker/git-repo.txt ;
    git log --pretty=fuller -n 1 >> $SETUP_INSTALL_PREFIX/server-docker/git-repo.txt ;
    cp -rfv $(git ls-tree -r --full-name HEAD | awk '{print $NF}') $SETUP_INSTALL_PREFIX/server-docker/ ;
fi

if [ -e "$SETUP_WORK_DIR" ]; then
    rm -rf $SETUP_WORK_DIR ;
    echo "Cleanup $SETUP_WORK_DIR done" ;
fi

cd ~ ;


# Ubuntu/Debian
if [ -e "/var/lib/apt/lists" ]; then
    for APT_CACHE in /var/lib/apt/lists/* ; do
        rm -rf "$APT_CACHE";
    done
fi

# CentOS/RedHat
which dnf 2>/dev/null && dnf clean all;
which yum 2>/dev/null && yum clean all;

# Test script

chmod +x /etc/profile.d/devnet.sh
chmod +x /opt/gcc/latest/load-gcc-envs.sh
chmod +x /opt/llvm/latest/load-llvm-envs.sh

source /etc/profile.d/devnet.sh
source /opt/gcc/latest/load-gcc-envs.sh
source /opt/llvm/latest/load-llvm-envs.sh


zsh --version
tmux -V
which p4 2>/dev/null && p4 -V
git --version
cmake --version
echo "ninja: $(ninja --version)"
go version
echo "nodejs: $(node --version)"
which dotnet 2>/dev/null && echo "dotnet-core: $(dotnet --version)"
which pwsh 2>/dev/null && pwsh --version
gcc -v
clang -v
