#!/bin/bash

DISTRIBUTE_NAME=$(cat /etc/os-release | perl -n -e'/^ID="?([^"]+)"?/ && print $1')
DISTRIBUTE_VERSION_ID=$(cat /etc/os-release | perl -n -e'/^VERSION_ID="?([^"]+)"?/ && print $1')
cat /etc/os-release  | grep 'ID_LIKE' | grep -i -E '(centos)|(rhel)' > /dev/null 2>&1 ;

if [ "x$DISTRIBUTE_NAME" == "xcentos" ]; then
    sed -i -r 's/#?\s*mirrorlist=/#mirrorlist=/g' /etc/yum.repos.d/CentOS-*.repo ;
    sed -i -r 's;#?\s*baseurl\s*=\s*http://[^\$]+\$contentdir;baseurl=http://mirrors.tencent.com/centos;g' /etc/yum.repos.d/CentOS-*.repo ;
    if [ "x$DISTRIBUTE_VERSION_ID" == "x8" ]; then
        dnf install -y epel-release ;
    else
        yum install -y epel-release ;
    fi
    sed -i -r 's/#?\s*metalink=/#metalink=/g' /etc/yum.repos.d/epel*.repo ;
    sed -i -r 's;#?\s*baseurl\s*=\s*https?://[^\$]+\$releasever;baseurl=http://mirrors.tencent.com/epel/\$releasever;g' /etc/yum.repos.d/epel*.repo ;
elif [ "x$DISTRIBUTE_NAME" == "xubuntu" ]; then
    if [ ! -e "/etc/apt/sources.list.bak" ]; then
        cp /etc/apt/sources.list /etc/apt/sources.list.bak ;
    fi

    sed -i -r 's;#?https?://archive.ubuntu.com/ubuntu/;http://mirrors.tencent.com/ubuntu/;g' /etc/apt/sources.list ;
    sed -i -r 's;#?https?://security.ubuntu.com/ubuntu/;http://mirrors.tencent.com/ubuntu-security/;g' /etc/apt/sources.list ;

    apt update -y;
elif [ "x$DISTRIBUTE_NAME" == "xdebian" ]; then
    if [ ! -e "/etc/apt/sources.list.bak" ]; then
        cp /etc/apt/sources.list /etc/apt/sources.list.bak ;
    fi

    sed -i -r 's;#?https?://.*/debian/;http://mirrors.tencent.com/debian/;g' /etc/apt/sources.list ;
    sed -i -r 's;#?https?://.*/debian-security/;http://mirrors.tencent.com/debian-security/;g' /etc/apt/sources.list ;

    apt update -y;
fi
