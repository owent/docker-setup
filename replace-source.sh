#!/bin/bash

if [ -e "/etc/os-release" ]; then
    DISTRIBUTE_NAME=$(cat /etc/os-release | awk 'BEGIN{FS="="} $1 == "ID" { print $2 }')
    DISTRIBUTE_VERSION_ID=$(cat /etc/os-release | awk 'BEGIN{FS="="} $1 ~ /^VERSION_ID/ { print $2 }')
    DISTRIBUTE_LIKE_NAMES=$(cat /etc/os-release | awk 'BEGIN{FS="="} $1 == "ID_LIKE" { print $2 }')
fi

if [ "x" == "x$DISTRIBUTE_NAME" ] && [ -e "/etc/arch-release" ]; then
    DISTRIBUTE_NAME=arch ;
elif [ "x" == "x$DISTRIBUTE_NAME" ] && [ -e "/etc/centos-release" ]; then
    DISTRIBUTE_NAME=centos ;
fi

# if [[ "${DISTRIBUTE_LIKE_NAMES[@]}" =~ centos22 ]]; then echo xxx; fi

DISTRIBUTE_NAME=${DISTRIBUTE_NAME//\"/};
DISTRIBUTE_LIKE_NAMES=${DISTRIBUTE_LIKE_NAMES//\"/};

if [ "x$DISTRIBUTE_NAME" == "xcentos" ] || [ "x$DISTRIBUTE_NAME" == "xrhel" ] || [[ "${DISTRIBUTE_LIKE_NAMES[@]}" =~ "centos" ]] || [[ "${DISTRIBUTE_LIKE_NAMES[@]}" =~ "rhel" ]]; then
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

    sed -i -r 's;#?https?://security.ubuntu.com/ubuntu/?[[:space:]];http://mirrors.tencent.com/ubuntu-security/ ;g' /etc/apt/sources.list ;
    sed -i -r 's;#?https?://archive.ubuntu.com/ubuntu/?[[:space:]];http://mirrors.tencent.com/ubuntu/ ;g' /etc/apt/sources.list ;

    apt update -y;
elif [ "x$DISTRIBUTE_NAME" == "xdebian" ] || [[ "${DISTRIBUTE_LIKE_NAMES[@]}" =~ "debian" ]]; then
    if [ ! -e "/etc/apt/sources.list.bak" ]; then
        cp /etc/apt/sources.list /etc/apt/sources.list.bak ;
    fi

    sed -i -r 's;#?https?://.*/debian-security/?[[:space:]];http://mirrors.tencent.com/debian-security/ ;g' /etc/apt/sources.list ;
    sed -i -r 's;#?https?://.*/debian/?[[:space:]];http://mirrors.tencent.com/debian/ ;g' /etc/apt/sources.list ;

    apt update -y;
elif [ "x$DISTRIBUTE_NAME" == "xalpine" ]; then
    sed -i.bak -r 's#dl-cdn.alpinelinux.org#mirrors.tencent.com#g' /etc/apk/repositories ;
elif [ "x$DISTRIBUTE_NAME" == "xmanjaro" ]; then
    sed -i -r '/Server\s*=\s*.*tencent.com/d' /etc/pacman.d/mirrorlist
    sed -i '1i Server = http://mirrors.tencent.com/manjaro/stable/$repo/$arch' /etc/pacman.d/mirrorlist
elif [ "x$DISTRIBUTE_NAME" == "xarch" ] || [[ "${DISTRIBUTE_LIKE_NAMES[@]}" =~ "arch" ]]; then
    sed -i -r '/Server\s*=\s*.*tencent.com/d' /etc/pacman.d/mirrorlist
    sed -i -r '/Server\s*=\s*.*aliyun.com/d' /etc/pacman.d/mirrorlist
    sed -i '1i Server = http://mirrors.aliyun.com/archlinux/$repo/os/$arch' /etc/pacman.d/mirrorlist
    sed -i '1i Server = https://mirrors.tencent.com/archlinux/$repo/os/$arch' /etc/pacman.d/mirrorlist
fi
