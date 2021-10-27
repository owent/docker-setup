#!/bin/bash

if [[ "x$SETUP_INSTALL_PREFIX" == "x" ]]; then
    export SETUP_INSTALL_PREFIX=/opt
fi

if [ "x$SETUP_WORK_DIR" == "x" ]; then
    export SETUP_WORK_DIR=/opt/setup/
fi

if [[ -e "$SETUP_WORK_DIR" ]]; then
    rm -rf $SETUP_WORK_DIR ;
    echo "Cleanup $SETUP_WORK_DIR done" ;
fi

cd ~ ;


# Ubuntu/Debian
if [[ -e "/var/lib/apt/lists" ]]; then
    for APT_CACHE in /var/lib/apt/lists/* ; do
        rm -rf "$APT_CACHE";
    done
fi

# CentOS/RedHat
which dnf 2>/dev/null && dnf clean all;
which yum 2>/dev/null && yum clean all;
