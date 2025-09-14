# README for router

## 虚拟机

### Clone后操作

改网卡UUID，否则ipv6走SLAAC会地址冲突。

```bash
sudo apt update -y && sudo apt upgrade -y
sudo apt install -y uuid
sudo bash -c '
for NM_IF in /etc/NetworkManager/system-connections/*.nmconnection; do
  NEW_UUID=$(uuid 2>&1 || uuidgen) && sed -i -E "s;uuid=[0-9A-Fa-f\\-]+;uuid=$NEW_UUID;I" "$NM_IF" && echo "$NM_IF -> uuid=$NEW_UUID";
done'
```

重置Host SSH key(debian/ubuntu)

```bash
sudo rm -rf /etc/ssh/ssh_host_*
sudo dpkg-reconfigure openssh-server
```

rlimit

```bash
echo "
*          hard    nofile     1048576
*          soft    nofile     4194304
root          hard    nofile     1048576
root          soft    nofile     4194304
" | sudo tee /etc/security/limits.d/80-nofile.conf
```

## Host machine

Lan bridge:  br0
> enp1s0f0, enp1s0f1, enp5s0

Wan: enp1s0f2, enp1s0f3
> Disable auto start

nftables 没找到类似 `ebtables -t broute -A BROUTING ... -j redirect --redirect-target DROP` 来改变FORWARD行为的方法。所以目前还是用了 `iptables` + `ebtables` 。
https://www.mankier.com/8/ebtables-nft#Bugs 这里目前说的是不支持，等哪天支持了可以切过去试试，脚本里的 `*.nft.sh` 是宿主机正常透明代理，子网还只能走基本的NAT的的脚本。

> 另： firewalld 会自动情况 iptables 规则和 ebtables 规则。所以母机上得自己设置安全选项

```bash
# Make sure iptable_nat is not loaded, @see https://wiki.nftables.org/wiki-nftables/index.php/Performing_Network_Address_Translation_(NAT)#Incompatibilities
# Install iptables-nft to replace dependencies to iptables of some packages
echo "## Do not load the iptable_nat,ip_tables,ip6table_nat,ip6_tables module on boot.
blacklist iptable_nat
blacklist ip6table_nat

# Upper script will disable auto load , or using scripts below to force disable modules
# install iptable_nat /bin/true
# install ip6table_nat /bin/true
" | sudo tee /etc/modprobe.d/disable-iptables.conf

cp -f kernel-modules-tproxy.conf /etc/modules-load.d/tproxy.conf ;
cp -f kernel-modules-ppp.conf /etc/modules-load.d/ppp.conf ;
cp -f kernel-modules-network-basic.conf /etc/modules-load.d/network-basic.conf ;

for MOD_FOR_ROUTER in $(cat /etc/modules-load.d/tproxy.conf); do
    modprobe $MOD_FOR_ROUTER;
done

# iptable_nat must not be loaded
for MOD_FOR_ROUTER in $(cat /etc/modules-load.d/network-basic.conf); do
    modprobe $MOD_FOR_ROUTER;
done

echo "
net.core.somaxconn = 16384
net.core.rmem_default = 1048576
net.core.rmem_max = 16777216
net.core.wmem_default = 1048576
net.core.wmem_max = 16777216
net.core.optmem_max = 65536
net.core.netdev_max_backlog = 16384
net.ipv4.tcp_rmem = 4096 262144 33554432
net.ipv4.tcp_wmem = 4096 65536 16777216
net.ipv4.udp_rmem_min = 8192
net.ipv4.udp_wmem_min = 8192
net.ipv4.tcp_mtu_probing=1
net.ipv4.tcp_syncookies=1
net.ipv4.tcp_tw_reuse=1
net.ipv4.tcp_fin_timeout=30
net.ipv4.tcp_fastopen=3
net.ipv4.tcp_max_syn_backlog=65536
net.ipv4.tcp_max_tw_buckets=65536
net.ipv4.tcp_keepalive_time = 150
net.ipv4.tcp_keepalive_intvl = 75
net.ipv4.tcp_keepalive_probes = 6
net.ipv4.ip_forward=1
net.ipv4.ip_forward_use_pmtu=1
net.ipv4.ip_local_port_range=10240 65000
net.ipv4.conf.all.promote_secondaries = 1
net.ipv4.conf.default.promote_secondaries = 1
net.ipv6.neigh.default.gc_thresh3 = 4096
net.ipv4.neigh.default.gc_thresh3 = 4096
net.ipv4.conf.all.forwarding=1
net.ipv4.conf.default.forwarding=1
net.ipv6.conf.all.forwarding=1
net.ipv6.conf.default.forwarding=1
net.ipv6.conf.all.accept_ra=2
net.ipv6.conf.default.accept_ra=2
# Configures below are used to support tproxy for bridge
net.bridge.bridge-nf-call-arptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-filter-vlan-tagged = 1
net.bridge.bridge-nf-pass-vlan-input-dev = 1
net.ipv4.conf.all.rp_filter=0
net.ipv4.conf.default.rp_filter=0
net.ipv4.conf.all.route_localnet=1
net.ipv4.conf.default.route_localnet=1
# All bridge interface should also be set
net.ipv4.conf.br0.rp_filter=0
net.ipv4.conf.enp1s0f0.rp_filter=0
net.ipv4.conf.enp1s0f1.rp_filter=0
net.ipv4.conf.br0.route_localnet=1
net.ipv4.conf.enp1s0f0.route_localnet=1
net.ipv4.conf.enp1s0f1.route_localnet=1
# NDP with radvd and dnsmasq enable ipv6 router advisement with ppp interface
net.ipv6.conf.all.proxy_ndp=1
net.ipv6.conf.default.proxy_ndp=1
net.ipv6.conf.br0.autoconf=0
" | sudo tee /etc/sysctl.d/91-forwarding.conf ;

echo "
# Disable local-link address for internal bridge(For IPv6 NAT)
# 接口启动可能在内核初始化 sysctl 之前，最好加到启动或刷新网络的回调里
# /etc/sysctl.d/95-interface-forwarding.conf : sysctl -p /etc/sysctl.d/95-interface-forwarding.conf
net.ipv6.conf.eno1.forwarding=1
net.ipv6.conf.eno1.proxy_ndp=1
# 开启转发的接口内核会关闭掉RA，需要重新设置一下
net.ipv6.conf.eno1.accept_ra=2
net.ipv6.conf.enp2s0.forwarding=1
net.ipv6.conf.enp2s0.proxy_ndp=1
net.ipv6.conf.enp2s0.accept_ra=2
# 配置里.是目录分隔符，要名字里包含.采用/代替(这里实际设备名是 enp2s0.5)
net.ipv6.conf.enp2s0/5.forwarding=1
net.ipv6.conf.enp2s0/5.proxy_ndp=1
net.ipv6.conf.enp2s0/5.accept_ra=2
# For all other interfaces set these 3 options
" | sudo tee /etc/sysctl.d/95-interface-forwarding.conf ;

echo "net.ipv4.ip_unprivileged_port_start=67
kernel.unprivileged_userns_clone=1
user.max_user_namespaces=28633

fs.inotify.max_user_instances=16384
fs.inotify.max_user_watches=1048576
" | sudo tee /etc/sysctl.d/92-container.conf ;

sysctl -p ;

# Check and enable bbr
find "/lib/modules/$(uname -r)" -type f -name '*.ko*' | awk '{if (match($0, /^\/lib\/modules\/([^\/]+).*\/([^\/]+)\.ko(\.[^\/\.]+)?$/, m)) {print m[1] " : " m[2];}}' | sort | uniq | grep tcp_bbr ;
if [ $? -eq 0 ]; then
    modprobe tcp_bbr ;
    if [ $? -eq 0 ]; then
        sed -i "/tcp_bbr/d" /etc/modules-load.d/*.conf ;
        sed -i "/net.core.default_qdisc/d" /etc/sysctl.d/*.conf;
        sed -i "/net.ipv4.tcp_congestion_control/d" /etc/sysctl.d/*.conf;
        echo "tcp_bbr" >> /etc/modules-load.d/network-bbr.conf ;
        echo "net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr" >> /etc/sysctl.d/91-forwarding.conf ;
    fi
fi

# rlimit
echo "
*          hard    nofile     1048576
*          soft    nofile     4194304
root          hard    nofile     1048576
root          soft    nofile     4194304
" | sudo tee /etc/security/limits.d/80-nofile.conf


# 开启 PMTUD
# @see https://wiki.archlinux.org/index.php/Ppp#Masquerading_seems_to_be_working_fine_but_some_sites_do_not_work
# @see https://www.mankier.com/8/nft#Statements-Extension_Header_Statement
# ipv4/tcp MSS: 1452=1500(max)-8(ppp)-20(ipv4)-20(tcp)
#   ipv4最多60字节扩展包头，实际使用建议至少减去常见扩展包头(VLAN数据帧（4字节）+MSS(4字节)+TSOPT(10字节)+对齐=20字节)
#   (ipv4最小MTU 576字节)
#   建议MSS: 1432/1412/1380
# ipv6/tcp MSS: 1432=1500(max)-8(ppp)-40(ipv6)-20(tcp)
#   ipv6动态扩展包头(对齐到8字节)+PMTU调整分片，但建议至少减去VLAN数据帧（4字节）
#   (ipv4最小MTU 1280字节)
#   基础包头长度:
#     逐跳选项包头(Hop-by-Hop Options Header): 最小8字节
#     路由包头(Routing Header): 典型值: 24/32字节
#     分片包头(Fragment Header): 8字节
#     认证包头(Authentication Header): 典型值: 24字节
#     目的地选项包头(Destination Options Header): 最小8字节
#   建议MSS: 1400/1380/1220
# 有一些VPN、代理还有额外数据帧包头。需要参考其协议继续缩减

# nftables: nft add rule inet nat FORWARD tcp flags syn counter tcp option maxseg size set rt mtu
# 这个选项也可以合入其他规则,没必要单独起一个
mkdir -p "/etc/nftables.conf.d"
echo "table inet network_basic {
  chain FORWARD {
    type filter hook forward priority filter; policy accept;
    tcp flags syn counter tcp option maxseg size set rt mtu
  }
}
" > /etc/nftables.conf.d/network-basic.conf
echo '[Unit]
Description=PMTU clamping for pppoe
Requires=network-online.target
After=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/sbin/nft -f /etc/nftables.conf.d/network-basic.conf
# oneshot will call stop after started immediately
# ExecStop=/usr/sbin/nft delete table inet network_basic

[Install]
WantedBy=multi-user.target
' > /lib/systemd/system/pmtu-clamping.service
systemctl enable pmtu-clamping
systemctl start pmtu-clamping

nft list chain inet nat FORWARD >/dev/null 2>&1
if [[ $? -ne 0 ]]; then
  nft add chain inet nat FORWARD '{ type filter hook forward priority filter ; }'
fi
nft add rule inet nat FORWARD tcp flags syn counter tcp option maxseg size set rt mtu

# iptables: iptables -I FORWARD -o ppp0 -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu
echo '[Unit]
Description=PMTU clamping for pppoe
Requires=network-online.target
After=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/sbin/iptables -I FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu

[Install]
WantedBy=multi-user.target
' > /lib/systemd/system/pmtu-clamping.service
systemctl enable pmtu-clamping
systemctl start pmtu-clamping
```

# 设置NetworkManager关闭ipv6的隐私模式（允许DHCPv6）
## ipv6.addr-gen-mode = default/stable-privacy/eui64
## 全局编辑 /etc/NetworkManager/NetworkManager.conf 添加
sudo bash -c 'echo "
[connection]
ipv6.addr-gen-mode=default-or-eui64
" >> /etc/NetworkManager/NetworkManager.conf'

## 单独iface
sudo nmcli conn modify "<iface>" ipv6.addr-gen-mode default-or-eui64

# IOMMU, IO直通()
## /etc/default/grub 的GRUB_CMDLINE_LINUX_DEFAULT里开 "quiet iommu=pt pcie_acs_override=downstream,multifunction pci=nommconf"
## # update-grub
### + For Intel CPUs (VT-d) set intel_iommu=on, unless your kernel sets the CONFIG_INTEL_IOMMU_DEFAULT_ON config option.
### + For AMD CPUs (AMD-Vi), IOMMU support is enabled automatically if the kernel detects IOMMU hardware support from the BIOS.
## # 对于 Intel CPU
## GRUB_CMDLINE_LINUX_DEFAULT="quiet intel_iommu=on iommu=pt initcall_blacklist=sysfb_init pcie_acs_override=downstream,multifunction pci=nommconf"
## # 对于 AMD CPU
## GRUB_CMDLINE_LINUX_DEFAULT="quiet iommu=pt initcall_blacklist=sysfb_init pcie_acs_override=downstream,multifunction pci=nommconf"
## # 其他的一些写法(如果是AMD处理器,将intel改为amd)
## GRUB_CMDLINE_LINUX_DEFAULT="quiet intel_iommu=on iommu=pt i915.enable_gvt=1 video=efifb:off" # 这是GVT模式，也就是共享模式，少部分cpu支持，但体验很好
## GRUB_CMDLINE_LINUX_DEFAULT="quiet intel_iommu=on iommu=pt video=efifb:off" # 这是独占模式，都支持，但显示器没有pve的控制台输出，也只能直通个一个虚拟机
## GRUB_CMDLINE_LINUX_DEFAULT="quiet intel_iommu=on iommu=pt pcie_acs_override=downstream,multifunction"
## GRUB_CMDLINE_LINUX_DEFAULT="quiet intel_iommu=on initcall_blacklist=sysfb_init pcie_acs_override=downstream,multifunction"
## # 参数释义
## 1.iommu=pt：启用 Intel VT-d 或 AMD-Vi 的 IOMMU。这是一种硬件功能，用于管理设备对系统内存的访问。在虚拟化环境中，启用 IOMMU 后，可以将物理设备直通到虚拟机中，以便虚拟机可以直接访问硬件设备。“iommu=pt”不是必须的，PT模式只在必要的时候开启设备的IOMMU转换，可以提高未直通设备PCIe的性能，建议添加。
## 2.initcall_blacklist=sysfb_init：禁用 sysfb_init 内核初始化函数。这个函数通常用于在内核启动过程中初始化系统帧缓冲。在使用 GPU 直通的情况下，这个函数可能会干扰直通操作，因此需要禁用它。
## 3.i915.enable_gvt=1：启用 Intel GVT-g 虚拟 GPU 技术。这个选项用于创建一个虚拟的 Intel GPU 设备，以便多个虚拟机可以共享物理 GPU 设备。启用 GVT-g 需要在支持虚拟 GPU 的 Intel CPU 和主板上运行，并且需要正确配置内核和虚拟机。想开启GVT-g的就添加这条，显卡直通的就不要添加了。
## 4.initcall_blacklist=sysfb_init：屏蔽掉pve7.2以上的一个bug，方便启动时候就屏蔽核显等设备驱动；
## 5.pcie_acs_override=downstream,multifunction：便于iommu每个设备单独分组，以免直通导致物理机卡死等问题
## 6.pci=nommconf：意思是禁用pci配置空间的内存映射,所有的 PCI 设备都有一个描述该设备的区域（您可以看到lspci -vv），访问该区域的最初方法是通过 I/O 端口，而 PCIe 允许将此空间映射到内存以便更简单地访问。
 
IOMMU_MODULES=($(find "/lib/modules/$(uname -r)" -type f -name '*.ko*' | awk '{if (match($0, /^\/lib\/modules\/([^\/]+).*\/([^\/]+)\.ko(\.[^\/\.]+)?$/, m)) {print m[2];}}' | sort | uniq | grep -E '^(vfio|virtio)'))
## 模块 vfio,vfio_iommu_type1,vfio-pci/vfio_pci
if [ ${#IOMMU_MODULES[@]} -gt 0 ]; then
    modprobe ${IOMMU_MODULES[@]}
    if [ $? -eq 0 ]; then
        for MOD_NAME in ${IOMMU_MODULES[@]}; do
          sed -i "/$MOD_NAME/d" /etc/modules-load.d/*.conf 
        done
        echo "$(echo ${IOMMU_MODULES[@]} | tr ' ' '\n')" >> /etc/modules-load.d/91-vm.conf
    fi
fi
## 检查IO直通
## @see https://wiki.archlinux.org/title/PCI_passthrough_via_OVMF
## @see https://forum.proxmox.com/threads/pci-gpu-passthrough-on-proxmox-ve-8-installation-and-configuration.130218/
dmesg | grep -e DMAR -e IOMMU
dmesg | grep 'remapping'
### 如果不支持 Interrupt remapping, 可以通过以下选项开启(注意可能和上面生成的模块加载选项冲突)
### echo "options vfio_iommu_type1 allow_unsafe_interrupts=1" > /etc/modprobe.d/iommu_unsafe_interrupts.conf
### 查询PCI接口设备
lspci -nn
for ETH_ID in $(lspci -nn | grep -i "Ethernet" | awk '{print $1}'); do
  lspci -vv -s $ETH_ID # Initial VFs: 64 表示最大支持 64 个 VF
done
### 查询虚拟分组
for g in $(find /sys/kernel/iommu_groups/* -maxdepth 0 -type d | sort -V); do
    echo "IOMMU Group ${g##*/}:"
    for d in $g/devices/*; do
        echo -e "\t$(lspci -nns ${d##*/})"
    done;
done;
## 创建 VF
### 手动创建
# 开启 8 个虚拟设置
echo 8 > /sys/class/net/${physic interface}/device/sriov_numvfs

# 关闭
echo 0 > /sys/class/net/${physic interface}/device/sriov_numvfs
### 自动创建
apt install sysfsutils -y
cat > /etc/sysfs.d/sr-iov.conf <<EOF
class/net/${physic interface}/device/sriov_numvfs = 8
EOF
systemctl enable sysfsutils --now

## r8125 驱动 (开启 debian的bookworm/non-free包和PVE的 bookworm/pve-no-subscription)
### 源码包
apt install -y r8125-dkms
### 安装编译依赖(PVE)
apt install -y dkms proxmox-default-headers
### 安装依赖(Debian)
apt install -y dkms linux-headers-amd64
### 编译(PVE,Debian不用编译)
dkms install \
  $(dkms status | grep r8125 | head -n 1 | awk '{print $1}' | awk 'BEGIN{FS=","}{print $1}')  \
  -k $(dpkg -l | awk '/^ii.+kernel-[0-9]+\.[0-9]+\.[0-9]/{gsub(/proxmox-kernel-|pve-kernel-|-signed/, ""); print $2}')
### 驱动签名(Debian不用编译也不用签名,自带的有签名)
mkdir -p /data/dkms
if [[ ! -e "/data/dkms/uefi-secure-boot-mok.der" ]]; then
  openssl req -new -x509 \
      -newkey rsa:2048 \
      -keyout /data/dkms/uefi-secure-boot-mok.key \
      -outform DER \
      -out /data/dkms/uefi-secure-boot-mok.der \
      -nodes -days 10950 \
      -subj "/CN=DKMS Signing MOK UEFI Secure Boot"

  # 密码需要反复输入，但是只需要一次（hg?）
  mokutil --import /data/dkms/uefi-secure-boot-mok.der
  # 然后需要去物理机器上启动，再Mok控制台输入这个密码
fi

echo '#!/bin/bash

KERNELVER=${KERNELVER:-$(uname -r)}

/lib/modules/"$KERNELVER"/build/scripts/sign-file sha512 /data/dkms/uefi-secure-boot-mok.key /data/dkms/uefi-secure-boot-mok.der "$2"
' > /data/dkms/sign-tool.sh
chmod +x /data/dkms/sign-tool.sh
sed -i 's;#[[:space:]]*sign_file[[:space:]]*=.*;sign_file="/data/dkms/sign-tool.sh";' /etc/dkms/framework.conf
dpkg-reconfigure r8125-dkms

## 启用驱动（务必重启后确认内核模块中包含 r8125: lsmod | grep r8125）
sed -i "/r8169/d" /etc/modprobe.d/dkms.conf
echo 'alias r8169 off' >> /etc/modprobe.d/dkms.conf
sed -i "/r8125/d" /etc/initramfs-tools/modules
sed -i "/r8169/d" /etc/initramfs-tools/modules
echo 'r8125' >> /etc/initramfs-tools/modules
echo 'r8169' >> /etc/initramfs-tools/modules
update-initramfs -k all -u
# reboot

**systemd-resolved will listen 53 and will conflict with our dnsmasq.service/smartdns.service**

sed -i -r 's/#?DNSStubListener[[:space:]]*=.*/DNSStubListener=no/g'  /etc/systemd/resolved.conf ;

systemctl disable systemd-resolved ;
systemctl stop systemd-resolved ;

systemctl enable NetworkManager ;
systemctl start NetworkManager ;

firewall-cmd --permanent --add-service=dns ;
firewall-cmd --permanent --add-service=dhcp ;
firewall-cmd --permanent --add-service=dhcpv6 ;
firewall-cmd --permanent --add-service=dhcpv6-client ;
firewall-cmd --permanent --add-service=dns-over-tls ;

# open 36000 for ssh forwarding
which firewall-cmd > /dev/null 2>&1 ;

if [ $? -eq 0 ]; then
    firewall-cmd --permanent --add-masquerade ;

    echo '<?xml version="1.0" encoding="utf-8"?>
<service>
    <short>redirect-sshd</short>
    <description>Redirect sshd</description>
    <port port="36000" protocol="tcp"/>
</service>
' | tee /etc/firewalld/services/redirect-sshd.xml ;

    # firewall-cmd --permanent --add-service=ssh ;
    firewall-cmd --permanent --add-service=redirect-sshd ;
    firewall-cmd --reload ;
    # firewall-cmd --query-masquerade ;
fi

if [[ -e  "/etc/security/limits.d" ]]; then
    echo "*          hard    nofile     1000000" | tee cat /etc/security/limits.d/99-nofile.conf
else
    sed -i '/hard    nofile     1000000/d' /etc/security/limits.conf
    echo "*          hard    nofile     1000000" >> /etc/security/limits.conf
fi
```

## Get My Ip

+ http://ifconfig.me
  + http://ifconfig.me/ip
+ https://ip.sb/
  + https://api.ip.sb/ip
+ https://ifconfig.io
  + https://ifconfig.io/ip
+ https://www.myip.la/
  + https://api.myip.la
+ https://www.ipify.org
  + https://api.ipify.org
+ http://getip.icu
+ http://myip.biturl.top
+ http://ip.threep.top

## Test script

```bash
echo "GET / HTTP/1.1
Host: myip.biturl.top
User-Agent: curl/7.64.0
Accept: */*

" | ncat --ssl --proxy 127.0.0.1:1080 --proxy-type socks5 myip.biturl.top 443
curl -vL --socks5 127.0.0.1:1080 myip.biturl.top

echo "GET / HTTP/1.1
Host: baidu.com
User-Agent: curl/7.64.0
Accept: */*

" | ncat -v --proxy 127.0.0.1:1080 --proxy-type socks5 baidu.com 80

```

## nftables Hook

| Type   | Families      | Hooks                                  | Description                                                                                                                                                                                                                                             |
| ------ | ------------- | -------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| filter | all           | all                                    | Standard chain type to use in doubt.                                                                                                                                                                                                                    |
| nat    | ip, ip6, inet | prerouting, input, output, postrouting | Chains of this type perform Native Address Translation based on conntrack entries. Only the first packet of a connection actually traverses this chain - its rules usually define details of the created conntrack entry (NAT statements for instance). |
| route  | ip, ip6       | output                                 | If a packet has traversed a chain of this type and is about to be accepted, a new route lookup is performed if relevant parts of the IP header have changed. This allows to e.g. implement policy routing selectors in nftables.                        |

## Standard priority names, family and hook compatibility matrix

> The priority parameter accepts a signed integer value or a standard priority name which specifies the order in which chains with same hook value are traversed. The ordering is ascending, i.e. lower priority values have precedence over higher ones.

| Name     | Value | Families                   | Hooks       |
| -------- | ----- | -------------------------- | ----------- |
| raw      | -300  | ip, ip6, inet              | all         |
| mangle   | -150  | ip, ip6, inet              | all         |
| dstnat   | -100  | ip, ip6, inet              | prerouting  |
| filter   | 0     | ip, ip6, inet, arp, netdev | all         |
| security | 50    | ip, ip6, inet              | all         |
| srcnat   | 100   | ip, ip6, inet              | postrouting |

## Standard priority names and hook compatibility for the bridge family

| Name   | Value | Hooks       |
| ------ | ----- | ----------- |
| dstnat | -300  | prerouting  |
| filter | -200  | all         |
| out    | 100   | output      |
| srcnat | 300   | postrouting |

## Public DNS

```bash
# DoH
kdig @<DNS IP> +tls-hostname=<DNS Domain> +fastopen +https=/dns-query <domain>
kdig @1.1.1.1 +https=/dns-query <domain>
kdig @8.8.8.8 +https=/dns-query <domain>
kdig @223.5.5.5 +https=/dns-query owent.net
# DoT
kdig @<DNS IP> +tls <domain>
kdig @1.1.1.1 +tls <domain>
kdig @8.8.8.8 +tls <domain>
kdig @223.5.5.5 +tls <domain>
```

See https://en.wikipedia.org/wiki/Public_recursive_name_server for more details

+ Dnspod
  + 119.29.29.29
  + 2402:4e00::
  + [DoH: RFC 8484][1] https://doh.pub/dns-query , 1.12.12.12 , 120.53.53.53 (不允许指定doh.pub为IP)
  + [DoT: RFC 7858][2] dot.pub , 1.12.12.12 , 120.53.53.53 (不允许指定dot.pub为IP)
  + [DNSCrypt][3] ```sdns://AgAAAAAAAAAAACDrdSX4jw2UWPgamVAZv9NMuJzNyVfnsO8xXxD4l2OBGAdkb2gucHViCi9kbnMtcXVlcnk```

  > Home: https://www.dnspod.cn/Products/Public.DNS
  > DoT/DoH: https://docs.dnspod.cn/public-dns/5fb5db1462110a2b153a77dd/

+ Aliyun
  + 223.5.5.5
  + 223.6.6.6
  + 2400:3200::1
  + 2400:3200:baba::1
  + [DoH: RFC 8484][1] https://dns.alidns.com/dns-query , https://[IP]/dns-query
  + [DoT: RFC 7858][2] dns.alidns.com , [IP]
  + [DNSCrypt][3] ```sdns://AgAAAAAAAAAACTIyMy41LjUuNSCoF6cUD2dwqtorNi96I2e3nkHPSJH1ka3xbdOglmOVkQ5kbnMuYWxpZG5zLmNvbQovZG5zLXF1ZXJ5```

  > Home: https://alidns.com/
  > DoT/DoH: https://alidns.com/knowledge?type=SETTING_DOCS

+ biigroup(天地互联)
  + 240c::6666
  + 240c::6644
  
  > https://www.biigroup.com/dns/s/?888.html

+ Baidu
  + 180.76.76.76
  + 2400:da00::6666
+ Google
  + 8.8.8.8
  + 8.8.4.4
  + 2001:4860:4860::8888
  + 2001:4860:4860::8844
  + [DoH: RFC 8484][1] https://dns.google/dns-query
  + [DoT: RFC 7858][2] dns.google
  + [DNSCrypt][3] ```sdns://AgUAAAAAAAAABzguOC44LjigHvYkz_9ea9O63fP92_3qVlRn43cpncfuZnUWbzAMwbkgdoAkR6AZkxo_AEMExT_cbBssN43Evo9zs5_ZyWnftEUKZG5zLmdvb2dsZQovZG5zLXF1ZXJ5```
  + [DNSCrypt][3] - ipv6 ```sdns://AgUAAAAAAAAAFlsyMDAxOjQ4NjA6NDg2MDo6ODg4OF2gHvYkz_9ea9O63fP92_3qVlRn43cpncfuZnUWbzAMwbkgdoAkR6AZkxo_AEMExT_cbBssN43Evo9zs5_ZyWnftEUKZG5zLmdvb2dsZQovZG5zLXF1ZXJ5```
+ Cloudflare
  + 1.1.1.1
  + 1.0.0.1
  + 2606:4700:4700::1111
  + 2606:4700:4700::1001
  + [DoH: RFC 8484][1] https://one.one.one.one/dns-query , https://[IP]/dns-query
  + [DoT: RFC 7858][2] one.one.one.one , [IP]
  + [DNSCrypt][3] ```sdns://AgcAAAAAAAAABzEuMC4wLjEAEmRucy5jbG91ZGZsYXJlLmNvbQovZG5zLXF1ZXJ5```
  + [DNSCrypt][3] - ipv6 ```sdns://AgcAAAAAAAAAFlsyNjA2OjQ3MDA6NDcwMDo6MTExMV0AIDFkb3QxZG90MWRvdDEuY2xvdWRmbGFyZS1kbnMuY29tCi9kbnMtcXVlcnk``` , ```sdns://AgcAAAAAAAAAFlsyNjA2OjQ3MDA6NDcwMDo6MTAwMV0AIDFkb3QxZG90MWRvdDEuY2xvdWRmbGFyZS1kbnMuY29tCi9kbnMtcXVlcnk```

  > DoT/DoH: https://developers.cloudflare.com/1.1.1.1/dns-over-https
  > `curl -H 'accept: application/dns-json' 'https://cloudflare-dns.com/dns-query?name=example.com'`

+ AdGuard
  + (拦截广告) 94.140.14.14
  + (拦截广告) 94.140.15.15
  + (拦截广告) 2a10:50c0::ad1:ff
  + (拦截广告) 2a10:50c0::ad2:ff
  + (无过滤) 94.140.14.140
  + (无过滤) 94.140.14.141
  + (无过滤) 2a10:50c0::1:ff
  + (无过滤) 2a10:50c0::2:ff
  + (家庭保护) 94.140.14.15
  + (家庭保护) 94.140.15.16
  + (家庭保护) 2a10:50c0::bad1:ff
  + (家庭保护) 2a10:50c0::bad2:ff
  + [DoH: RFC 8484][1]
    + (拦截广告) https://dns.adguard.com/dns-query
    + (无过滤) https://dns-unfiltered.adguard.com/dns-query
    + (家庭保护) https://dns-family.adguard.com/dns-query
    + `https://[IP]/dns-query`
  + [DoT: RFC 7858][2]
    + (拦截广告) dns.adguard.com
    + (无过滤) dns-unfiltered.adguard.com
    + (家庭保护) dns-family.adguard.com
    + `[IP]`
  + [DoQ: Draft][4]
    + (拦截广告) quic://dns.adguard.com
    + (无过滤) quic://dns-unfiltered.adguard.com
    + (家庭保护) quic://dns-family.adguard.com
  + [DNSCrypt][3]
    + (拦截广告) sdns://AQMAAAAAAAAAETk0LjE0MC4xNC4xNDo1NDQzINErR_JS3PLCu_iZEIbq95zkSV2LFsigxDIuUso_OQhzIjIuZG5zY3J5cHQuZGVmYXVsdC5uczEuYWRndWFyZC5jb20
    + (无过滤) sdns://AQMAAAAAAAAAEjk0LjE0MC4xNC4xNDA6NTQ0MyC16ETWuDo-PhJo62gfvqcN48X6aNvWiBQdvy7AZrLa-iUyLmRuc2NyeXB0LnVuZmlsdGVyZWQubnMxLmFkZ3VhcmQuY29t
    + (家庭保护) sdns://AQMAAAAAAAAAETk0LjE0MC4xNC4xNTo1NDQzILgxXdexS27jIKRw3C7Wsao5jMnlhvhdRUXWuMm1AFq6ITIuZG5zY3J5cHQuZmFtaWx5Lm5zMS5hZGd1YXJkLmNvbQ

  > https://adguard-dns.io/zh_cn/public-dns.html
  > https://adguard-dns.io/en/public-dns.html

+ NextDNS(需要注册账号) - https://my.nextdns.io/
  + IP(需绑定白名单):
    + 45.90.28.71
    + 45.90.30.71
    + 2a07:a8c0::d1:bc18
    + 2a07:a8c1::d1:bc18
  + [DoT: RFC 7858][2] / [DoQ: Draft][4]
    + `<租户ID>.dns.nextdns.io`
  + [DoH: RFC 8484][1]
    + (拦截广告) https://dns.nextdns.io/<租户ID>

+ Quad9
  + 9.9.9.9
  + 149.112.112.112
  + 2620:fe::10
  + 2620:fe::fe:10
  + [DoT: RFC 7858][2] dns.quad9.net
  + [DoT: RFC 7858][2] [IP]
+ OpenDNS
  + 208.67.222.222
  + 208.67.220.220
  + 2620:119:35::35
  + 2620:119:53::53

> [DoT: RFC 7858][2] port: 853

## China Domain List

+ https://github.com/felixonmars/dnsmasq-china-list
+ CDN:
  + https://cdn.jsdelivr.net/gh/felixonmars/dnsmasq-china-list/accelerated-domains.china.conf
  + https://cdn.jsdelivr.net/gh/felixonmars/dnsmasq-china-list/apple.china.conf
  + https://cdn.jsdelivr.net/gh/felixonmars/dnsmasq-china-list/bogus-nxdomain.china.conf
  + https://cdn.jsdelivr.net/gh/felixonmars/dnsmasq-china-list/google.china.conf

## 桥接设置VLAN Tag参考(未测试)

参考 `man bridge` / https://www.man7.org/linux/man-pages/man8/bridge.8.html 

```bash
BRIDGE_IFNAME=br0
BRIDGE_TARGET_IFNAMES=(enp7s0 enp8s0)
BRIDGE_TARGET_VLAN_ID=3

# 对外透明
for BRIDGE_TARGET_IFNAME in ${BRIDGE_TARGET_IFNAME[@]}; do
  # 指定接口入流量打 VLAN tag，出流量 untagged（允许打多个tag）
  bridge vlan add vid $BRIDGE_TARGET_VLAN_ID pvid untagged dev $BRIDGE_TARGET_IFNAME
  # 指定接口入流量打 VLAN tag（允许打多个tag）
  # bridge vlan add vid $BRIDGE_TARGET_VLAN_ID pvid untagged dev $BRIDGE_TARGET_IFNAME
  # 删除默认tag
  bridge vlan del vid 1 dev $BRIDGE_TARGET_IFNAME
done
# 是否可以直接? bridge vlan add vid $BRIDGE_TARGET_VLAN_ID pvid untagged dev $BRIDGE_IFNAME self

# 对外tag
for BRIDGE_TARGET_IFNAME in ${BRIDGE_TARGET_IFNAME[@]}; do
  # 指定接口出入流量都打 VLAN tag（允许打多个tag）
  bridge vlan add vid $BRIDGE_TARGET_VLAN_ID dev $BRIDGE_TARGET_IFNAME
  # 删除默认tag
  bridge vlan del vid 1 dev $BRIDGE_TARGET_IFNAME
done
# 是否可以直接? bridge vlan add vid $BRIDGE_TARGET_VLAN_ID dev $BRIDGE_IFNAME self

# 删除默认 vlan tag
bridge vlan del vid 1 dev $BRIDGE_IFNAME self

# 开启桥接的 vlan_filtering ， 仅仅用于使用桥接管理多个子vlan。如果是上级vlan转发到此bridge请不要开启
# 注意试一下 ip route get <ip> 和 ping <ip> 确保链路路由正常
# 参考: https://developers.redhat.com/blog/2017/09/14/vlan-filter-support-on-bridge
# ip link add $BRIDGE_IFNAME type bridge vlan_filtering 1
ip link set $BRIDGE_IFNAME type bridge vlan_filtering 1

# 默认VLAN，不一定需要
# ip link set $BRIDGE_IFNAME type bridge vlan_default_pvid $BRIDGE_TARGET_VLAN_ID
```

## Podman/docker 代理

### podman 代理

文件: `/etc/containers/registries.conf.d/docker.io.conf`

```toml
[[registry]]
prefix = "docker.io"
blocked = false
location = "mirror.ccs.tencentyun.com"
```

### docker 代理

文件: `/etc/docker/daemon.json`

```toml
{
  "registry-mirrors": ["mirror.ccs.tencentyun.com"]
}
```

### 公共镜像站

+ <mirror.ccs.tencentyun.com> (仅腾讯云内网)
+ <docker.m.daocloud.io> (部分)
+ <docker.1ms.run>
+ <docker.xuanyuan.me>
+ <docker.hlmirror.com>

## Podman/docker 存储设置

### 文件系统

| 类型  | 应用场景 | 建议选项                                                                  |
| ----- | -------- | ------------------------------------------------------------------------- |
| btrfs | SSD      | rw,noatime,compress=zstd:1,ssd,autodefrag,user_subvol_rm_allowed,subvol=/ |
| xfs   | SSD      | rw,noatime,largeio,inode64,allocsize=128m,logbufs=8,logbsize=256k,noquota |
| xfs   | 网络存储 | rw,noatime,largeio,inode64,allocsize=128m,logbufs=8,swalloc,noquota       |

### podman 存储

文件: `/etc/containers/storage.conf` 或 `$HOME/.config/containers/storage.conf`

```toml
[storage]
driver = "overlay"
runroot = "/data/disk1/docker-container"
graphroot = "/data/disk1/docker-image"
rootless_storage_path = "/data/disk1/docker-storage/$USER"
```

临时目录 - 文件: `/etc/containers/containers.conf` 或 `$HOME/.config/containers/containers.conf`

```toml
[engine]
env = ["TMPDIR=/data/disk1/docker-tmp"]
```

### podman 限制日志大小

文件: `/etc/containers/libpod.conf` 或 `$HOME/.config/containers/libpod.conf`

```toml
max_log_size = 134217728 # 128MB
# max_log_size = 33554432 # 32MB
```

### docker 存储

文件: `/etc/docker/daemon.json`

```json
{
    "graph": "/data/docker-data",
    "storage-driver": "overlay",
    "insecure-registries" : [ "docker.io" ]
}
```

### docker 限制日志大小

文件: `/etc/docker/daemon.json`

```json
{
  "log-driver": "json-file",
    "log-opts": {
      "max-size": "128m",
      "max-file": "3",
      "labels": "production_status",
      "env": "os,customer"
    }
}
```

## Rust公共代理

```bash
if [[ -z "$RUSTUP_DIST_SERVER" ]]; then
  export RUSTUP_DIST_SERVER="https://rsproxy.cn"
  # export RUSTUP_DIST_SERVER=https://mirrors.ustc.edu.cn/rust-static
  # export RUSTUP_DIST_SERVER=https://mirrors.tuna.tsinghua.edu.cn/rustup
fi
if [[ -z "$RUSTUP_UPDATE_ROOT" ]]; then
  export RUSTUP_UPDATE_ROOT="https://rsproxy.cn/rustup"
  # export RUSTUP_UPDATE_ROOT=https://mirrors.ustc.edu.cn/rust-static/rustup
  # export RUSTUP_UPDATE_ROOT=https://mirrors.tuna.tsinghua.edu.cn/rustup/rustup
fi
```

文件: `~/.cargo/config`

```toml
[source.crates-io]
replace-with = 'rsproxy-sparse'
# replace-with = 'ustc'
# replace-with = 'tuna'
[source.rsproxy]
registry = "https://rsproxy.cn/crates.io-index"
[source.rsproxy-sparse]
registry = "sparse+https://rsproxy.cn/index/"
[registries.rsproxy]
index = "https://rsproxy.cn/crates.io-index"
[net]
git-fetch-with-cli = true

# USTC
[source.ustc]
registry = "sparse+https://mirrors.ustc.edu.cn/crates.io-index/"

[registries.ustc]
index = "sparse+https://mirrors.ustc.edu.cn/crates.io-index/"

# TUNA
[source.tuna]
registry = "sparse+https://mirrors.tuna.tsinghua.edu.cn/crates.io-index/"

[registries.tuna]
index = "sparse+https://mirrors.tuna.tsinghua.edu.cn/crates.io-index/"
```

## Rust 编译OOM问题

+ 降低编译并发数: `export CARGO_BUILD_JOBS=1` / `cargo build --jobs 1` / `cargo install --jobs 1`
+ 使用内存占用更低的链接器: `export RUSTFLAGS="-C link-arg=-fuse-ld=lld"`
+ 降低代码单元数: 编译 `Cargo.toml` 文件

>```toml
>[profile.release]
>codegen-units = 1
>```
>

### ipv6

## ipv6 国内测试

- <https://testipv6.cn/>
- <https://ipw.cn/>
- <https://ipv6ready.me/>

## DHCPv6测试

```bash
# 测试 DHCPv6 客户端请求
sudo dhclient -6 -v eth0

# 释放 DHCPv6 地址
sudo dhclient -6 -r eth0

# 指定配置文件测试
sudo dhclient -6 -cf /etc/dhcp/dhclient6.conf eth0
```

## RA测试

```bash

# apt install ndisc6
# 发送路由器请求并监听RA
rdisc6 eth0

# 指定接口监听RA
rdisc6 -1 eth0  # 只接收一个RA包后退出

#################################################
# 抓取ICMPv6包（包含RA）
tcpdump -vv -tttt -i eth0 icmp6

# 更具体的RA包过滤
tcpdump -vv -tttt -i eth0 'icmp6 and ip6[40] == 134'
```

[1]: https://tools.ietf.org/html/rfc8484 "RFC 8484"
[2]: https://tools.ietf.org/html/rfc7858 "RFC 7858"
[3]: https://dnscrypt.info/ "DNSCrypt"
[4]: https://datatracker.ietf.org/doc/draft-ietf-dprive-dnsoquic/ "DNS over Dedicated QUIC Connections(Draft)"

