#!/bin/bash

# 设置限制内存使用
# (查看当前上限)
cat /sys/module/zfs/parameters/zfs_arc_max
# (查看当前状态)
cat /proc/spl/kstat/zfs/arcstats | egrep '^(hits|misses|size|c_max|c_min)'

# 设置为 4GB，建议值如下
## 8GB 内存机器：2G ~ 4G
## 16GB 内存机器：4G ~ 8G
## 如果机器还跑数据库、虚拟机、容器：建议给 ZFS 留少一点
## 随机读多：更依赖 ARC, 如果 arcstats 的 misses 过多，iostat -x 1 的 await 过高，可以考虑增加 ARC 大小
# echo "options zfs zfs_arc_max=4294967296" | sudo tee /etc/modprobe.d/zfs-arc.conf
echo "options zfs zfs_arc_min=1073741824 zfs_arc_max=4294967296" | sudo tee /etc/modprobe.d/zfs-arc.conf
# 更新 initramfs
sudo update-initramfs -u -k all && sudo reboot

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
