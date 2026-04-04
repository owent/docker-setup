#!/bin/bash

export DEBIAN_FRONTEND=noninteractive

echo 'Acquire::https::mirrors.tencent.com::Verify-Peer "false";' > /etc/apt/apt.conf.d/99ignore-ssl-mirrors-tencent
echo 'Acquire::https::mirrors.tencent.com::Verify-Host "false";' >> /etc/apt/apt.conf.d/99ignore-ssl-mirrors-tencent
echo 'Acquire::https::mirrors.ustc.edu.cn::Verify-Peer "false";' > /etc/apt/apt.conf.d/99ignore-ssl-mirrors-ustc
echo 'Acquire::https::mirrors.ustc.edu.cn::Verify-Host "false";' >> /etc/apt/apt.conf.d/99ignore-ssl-mirrors-ustc


if [ -e "/etc/apt/sources.list" ]; then
  if [ ! -e "/etc/apt/sources.list.bak" ]; then
    cp /etc/apt/sources.list /etc/apt/sources.list.bak
  fi

  sed -i -r 's;https?://.*/(debian-security/?);http://mirrors.ustc.edu.cn/\1;g' /etc/apt/sources.list
  sed -i -r 's;https?://.*/(debian/?);http://mirrors.ustc.edu.cn/\1;g' /etc/apt/sources.list
fi

if [ -e "/etc/apt/sources.list.d/debian.sources" ]; then
  if [ ! -e "/etc/apt/sources.list.d/debian.sources.bak" ]; then
    cp /etc/apt/sources.list.d/debian.sources /etc/apt/sources.list.d/debian.sources.bak
  fi
  sed -i -r 's;https?://.*/(debian-security/?);http://mirrors.ustc.edu.cn/\1;g' /etc/apt/sources.list.d/debian.sources
  sed -i -r 's;https?://.*/(debian/?);http://mirrors.ustc.edu.cn/\1;g' /etc/apt/sources.list.d/debian.sources
fi

apt update -y || apt update -y || apt update -y
apt upgrade -y || apt upgrade -y || apt upgrade -y

apt install -y vim curl wget git git-lfs sudo jq ripgrep yq ffmpeg bash ca-certificates
apt install -y tzdata less iproute2 gawk lsof openssh-client gpg dnsutils telnet knot-dnsutils
apt install -y sysstat traceroute tcptraceroute tcpdump netcat-openbsd ncat nftables
apt install -y python3 python3-pip python3-wheel python3-setuptools python3-virtualenv
apt install -y gh golang

sudo update-ca-certificates
