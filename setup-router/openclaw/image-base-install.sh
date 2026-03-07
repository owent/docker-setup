#!/bin/bash

export DEBIAN_FRONTEND=noninteractive

echo 'Acquire::https::mirrors.tencent.com::Verify-Peer "false";' > /etc/apt/apt.conf.d/99ignore-ssl-mirrors-tencent ;
echo 'Acquire::https::mirrors.tencent.com::Verify-Host "false";' >> /etc/apt/apt.conf.d/99ignore-ssl-mirrors-tencent ;

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

# p4
wget -qO - https://package.perforce.com/perforce.pubkey | gpg --dearmor | tee /usr/share/keyrings/perforce.gpg > /dev/null
echo "deb [signed-by=/usr/share/keyrings/perforce.gpg] https://package.perforce.com/apt/ubuntu jammy release" | tee /etc/apt/sources.list.d/perforce.list

apt update -y || apt update -y || apt update -y
apt upgrade -y || apt upgrade -y || apt upgrade -y

apt install -y vim curl wget git git-lfs sudo jq ripgrep yq ffmpeg ca-certificates
apt install -y gh

sudo update-ca-certificates
