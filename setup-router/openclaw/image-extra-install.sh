#!/bin/bash

export DEBIAN_FRONTEND=noninteractive

# apt install -y subversion

# p4
mkdir -p /usr/share/keyrings
curl -k -L https://package.perforce.com/perforce.pubkey -o /usr/share/keyrings/perforce.pubkey || \
  curl -k -L https://package.perforce.com/perforce.pubkey -o /usr/share/keyrings/perforce.pubkey ||
  curl -k -L https://package.perforce.com/perforce.pubkey -o /usr/share/keyrings/perforce.pubkey
cat /usr/share/keyrings/perforce.pubkey | gpg --dearmor -o /usr/share/keyrings/perforce.gpg
echo 'Acquire::https::package.perforce.com::Verify-Peer "false";' > /etc/apt/apt.conf.d/99ignore-ssl-package-perforce
echo 'Acquire::https::package.perforce.com::Verify-Host "false";' >> /etc/apt/apt.conf.d/99ignore-ssl-package-perforce

echo "deb [signed-by=/usr/share/keyrings/perforce.gpg] https://package.perforce.com/apt/ubuntu jammy release" | tee /etc/apt/sources.list.d/perforce.list

apt update -y || apt update -y || apt update -y
apt install -y helix-cli || apt install -y helix-cli || apt install -y helix-cli

apt clean -y
