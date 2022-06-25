#!/bin/bash

sed -i.bak -r 's#dl-cdn.alpinelinux.org#mirrors.tencent.com#g' /etc/apk/repositories

SMB_USER_NAME='owent'
SMB_USER_PASSWORD='PASSWORD'
SMB_DATA_DIR='/data'
set -x
apk add --no-cache samba samba-client nfs-utils
useradd -M -s /sbin/nologin $SMB_USER_NAME
echo "$SMB_USER_PASSWORD" | passwd --stdin $SMB_USER_NAME
echo "$SMB_USER_PASSWORD" | passwd --stdin root
(
  echo "$SMB_USER_PASSWORD"
  echo "$SMB_USER_PASSWORD"
) | smbpasswd -a $SMB_USER_NAME -s
dnf clean all
systemctl enable smb
systemctl enable nmb
mkdir -p /data/logs/samba
chmod 777 -R "$SMB_DATA_DIR"

echo '#!/bin/bash
mkdir -p /run/samba
exec /usr/sbin/smbd -F --no-process-group -s /etc/samba/smb.conf
' >/usr/sbin/start-smbd.sh
chmod +x /usr/sbin/start-smbd.sh
