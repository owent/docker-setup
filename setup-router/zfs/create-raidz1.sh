#!/bin/bash

# 安装模块
sudo apt install -y zfsutils-linux zfs-dkms zfs-zed

# 找到要用的硬盘（by-id）后
sudo zpool create -f \
  -o ashift=12 \
  -o autotrim=on \
  -O compression=lz4 \
  -O atime=off \
  -O xattr=sa \
  -O acltype=posixacl \
  -O dnodesize=auto \
  -O mountpoint=/data/zfs/d1 \
  zfs-d1 raidz1 \
/dev/disk/by-id/nvme-ZHITAI_TiPlus7100_4TB_ZTA54T0AB2525235P9 \
/dev/disk/by-id/nvme-ZHITAI_TiPlus7100_4TB_ZTA54T0AB252650AM2 \
/dev/disk/by-id/nvme-ZHITAI_TiPlus7100_4TB_ZTA54T0AB25323010N \
/dev/disk/by-id/nvme-ZHITAI_TiPlus7100_4TB_ZTA54T0AB2532307K0


# 检查状态
zpool status
zpool list
zfs list

# 开机自动导入和挂载

sudo zpool set cachefile=/etc/zfs/zpool.cache zfs-d1
zpool get cachefile zfs-d1

sudo systemctl enable zfs-import-cache.service
sudo systemctl enable zfs-mount.service
sudo systemctl enable zfs.target

sudo systemctl start zfs-import-cache.service
sudo systemctl start zfs-mount.service


# 开启定期巡检
sudo systemctl enable --now zfs-scrub-monthly@zfs-d1.timer

## 手动巡检一次
sudo zpool scrub zfs-d1
## 查看进度
zpool status
