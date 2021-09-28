# Docker Setup Script

## 系统

```bash
# 对用户启用systemd支持
sudo loginctl enable-linger <用户名>
```

## 启动命令备注

```bash
# 带systemd
podman run docker run -d --systemd true IMAGE /sbin/init

## systemd expects to have /run, /run/lock and /tmp on tmpfs
## It also expects to be able to write to /sys/fs/cgroup/systemd and /var/log/journal
## docker run -d --cap-add=SYS_ADMIN -v /sys/fs/cgroup:/sys/fs/cgroup IMAGE /sbin/init
## Mount list come from setupSystemd@libpod/container_internal_linux.go on https://github.com/containers/libpod
docker build --tag router-base -f debian10.router.raw.Dockerfile
docker run -d --name router --cap-add=SYS_ADMIN                                             \
        --mount type=tmpfs,target=/run,tmpfs-mode=1777,tmpfs-size=67108864                  \
        --mount type=tmpfs,target=/run/lock,tmpfs-mode=1777,tmpfs-size=67108864             \
        --mount type=tmpfs,target=/tmp,tmpfs-mode=1777                                      \
        --mount type=tmpfs,target=/var/log/journal,tmpfs-mode=1777                          \
        --mount type=bind,source=/sys/fs/cgroup,target=/sys/fs/cgroup                       \
        IMAGE /sbin/init
        # --mount type=bind,source=/sys/fs/cgroup/systemd,target=/sys/fs/cgroup/systemd

# 路由
podman build --tag router-base -f debian10.router.raw.Dockerfile
podman run -d --name router --systemd true                                                  \
       --mount type=bind,source=/home/router,target=/home/router                            \
       --mount type=bind,source=/opt/nftables,target=/opt/nftables,ro=true                  \
       --cap-add=NET_ADMIN --network=host router-base /sbin/init

podman run -d --name router --systemd true                                                  \
       --mount type=bind,source=/home/router,target=/home/router                            \
       --cap-add=NET_ADMIN --network=host router-base /lib/systemd/systemd

# @see https://docs.docker.com/engine/reference/builder/#entrypoint for detail about CMD and ENTRYPOINT

# 查看当前内核所有可用的模块
find /lib/modules/$(uname -r) -type f -name '*.ko*' | xargs basename -a | sort | uniq

# 查看已安装的内核所有可用的模块
find /lib/modules/ -type f -name '*.ko*' | awk '{if (match($0, /^\/lib\/modules\/([^\/]+).*\/([^\/]+)\.ko(\.[^\/\.]+)?$/, m)) {print m[1] " : " m[2];}}' | sort | uniq

# 查看和管理当前内核加载的模块信息
insmod/modprobe # 加载
rmmod           # 卸载
lsmod           # 查看系统中所有已经被加载了的所有的模块以及模块间的依赖关系
modinfo         # 获得模块的信息
cat /proc/modules  # 能够显示模块大小、在内核空间中的地址
cat /proc/devices  # 只显示驱动的主设备号，且是分类显示
ls /sys/modules    # 下面存在对应的驱动的目录，目录下包含驱动的分段信息等等。  
```

### 配置firewalld

```bash
apt/dnf/yum install firewalld;
systemctl enable firewalld;
systemctl start firewalld;
vim /etc/firewalld/firewalld.conf ; # using FirewallBackend=nftables
firewall-cmd --permanent --add-service=dhcp;
firewall-cmd --permanent --add-service=dhcpv6;
firewall-cmd --permanent --add-service=dhcpv6-client;
firewall-cmd --permanent --add-service=dns;
firewall-cmd --permanent --add-service=ssh;
# firewall-cmd --permanent --add-service=custom services;
# firewall-cmd --permanent --add-port=custom tcp port/tcp;
# firewall-cmd --permanent --add-port=custom udp port/udp;
firewall-cmd --reload ;
firewall-cmd --list-all ;
```

## 文档地址备注

+ kernel latest: https://www.kernel.org/doc/html/latest/ , https://www.kernel.org/doc/Documentation/
+ kernel 5.3.X: https://www.kernel.org/doc/html/v5.3/ , https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git/tree/Documentation?h=v5.3
+ nftables: https://www.netfilter.org/projects/nftables/manpage.html
+ nftables: https://www.mankier.com/8/nft
+ nftables: https://wiki.nftables.org/wiki-nftables/index.php/Quick_reference-nftables_in_10_minutes
+ 已分配IP地址范围: http://ftp.apnic.net/apnic/stats/apnic/delegated-apnic-latest
+ dnsmasq: http://www.thekelleys.org.uk/dnsmasq/docs/dnsmasq-man.html
+ DNS over HTTPS/TLS: https://dnscrypt.info/
+ DNS ranking: https://www.dnsperf.com/#!dns-resolvers
+ DHCP & BOOT options: https://www.iana.org/assignments/bootp-dhcp-parameters
+ DHCPv6 options: https://www.iana.org/assignments/dhcpv6-parameters
+ IPv4 Specification: https://tools.ietf.org/html/rfc791#section-3.1
+ IPv6 Specification: https://tools.ietf.org/html/rfc8200#section-3
+ TCP Specification: https://tools.ietf.org/html/rfc793#page-15 , https://en.wikipedia.org/wiki/Transmission_Control_Protocol
+ UDP Specification: https://tools.ietf.org/html/rfc768 , https://en.wikipedia.org/wiki/User_Datagram_Protocol
+ ICMP: https://tools.ietf.org/html/rfc792#page-4 , https://en.wikipedia.org/wiki/Internet_Control_Message_Protocol
+ ICMPv6: https://tools.ietf.org/html/rfc4443#section-2.1 , https://en.wikipedia.org/wiki/Internet_Control_Message_Protocol_for_IPv6


## 更新内核备注

```bash
## CentOS - add elrepo from http://elrepo.org/tiki/tiki-index.php
yum/dnf --enablerepo=elrepo-kernel install kernel-ml kernel-ml-core kernel-ml-modules kernel-ml-devel kernel-ml-modules-extra

if [[ "x$NEED_KERNEL_TOOLS" != "x" ]] || [[ "x$NEED_REBUILD_GLIBC" != "x" ]]; then
    yum/dnf remove -y kernel-headers kernel-tools kernel-tools-libs ;
    yum/dnf --enablerepo=elrepo-kernel install -y kernel-ml-tools kernel-ml-tools-libs ;
fi
if [[ "x$NEED_REBUILD_GLIBC" != "x" ]]; then
    yum/dnf remove -y kernel-headers ;
    yum/dnf --enablerepo=elrepo-kernel install -y kernel-ml-headers ;
    # install gcc again
    yum/dnf install -y gcc gcc-c++ libtool ;
    yum/dnf --enablerepo=elrepo-kernel update -y;
fi

### Update boot order - CentOS/RHEL 8 only
for KERNEL_PATH in /boot/vmlinuz-* ; do 
    printf "============ %s ============\n%s\n" "$KERNEL_PATH" "$(grubby --info=$KERNEL_PATH)";
done
grubby --make-default ;
echo "Current boot -> Kernel: $(grubby --default-kernel), Index: $(grubby --default-index)" ;

### Update boot order - CentOS/RHEL 7 only
awk -F\' '$1=="menuentry " {print $2}' /etc/grub2.cfg ;
SELECT_KERNEL_INDEXS=($(awk -F\' '$1=="menuentry " {print $2}' /etc/grub2.cfg | grep -n '[(]\s*[4-9]\.' | cut -d: -f 1));
if [ ${#SELECT_KERNEL_INDEXS} -gt 0 ]; then
    ((SELECT_KERNEL_INDEX=${SELECT_KERNEL_INDEXS[0]}-1));
    grub2-set-default $SELECT_KERNEL_INDEX ;
    echo "Now, you can reboot to use kernel $(awk -F\' '$1=="menuentry " {print $2}' /etc/grub2.cfg | grep '[(]\s*[4-9]\.' | head -n 1) ";
    echo -e "Please to rerun this script if you want to update componments in this system, or use \\033[33;1myum --enablerepo=elrepo-kernel update -y\\033[0m to update system";
else
    echo -e "\\033[31;1mError: kernel 4.X or upper not found.\\033[0m";
fi

## Ubuntu - download from https://kernel.ubuntu.com/~kernel-ppa/mainline/ or run scripts below
apt search "linux-image-" | awk '$0 ~ /linux-image-[0-9\.-]+-generic/ {print $0}' ;
apt install linux-image-<VERSION>-generic

## Debian
apt search linux-image;
apt install linux-image-<VERSION>
```

## Docker备注

```yum/apt install -y docker-ce``` 或 ```dnf install -y podman```

```bash
# 手动设置docker需要的网桥
sudo brctl addbr docker0
sudo ip addr add 192.168.10.1/24 dev docker0
sudo ip link set dev docker0 up
ip addr show docker0

# 代理必须在启动脚本加环境变量
HTTP_PROXY=$http_proxy
HTTPS_PROXY=$https_proxy
NO_PROXY=$no_proxy

# /etc/docker/daemon.json 里可配不用验证证书的服务和存储位置
{
    "graph": "/data/docker-data",
    "storage-driver": "overlay",
    "insecure-registries" : [ "docker.io" ]
}

```

## ```systemd/journald``` 备注

### 日志

```bash
echo "$LOG_CONTENT" | systemd-cat -t TARGET_NAME -p info ; # Write log
journalctl -t TARGET_NAME ; # Review log
```

Configure GC of journal

```bash
# Usage
journalctl --disk-usage
du -sh /var/log/journal/

# Rotate and cleanup
journalctl --rotate

# Clear journal log older than x days
journalctl --vacuum-time=2d

# Restrict logs to a certain size
journalctl --vacuum-size=100M

# Restrict number of log files
journalctl --vacuum-files=5
```

Auto cleanup: edit ```/etc/systemd/journald.conf```

```bash
systemctl restart systemd-journald
```

## 常见错误

+ podman启动报 `Error: OCI runtime error: container_linux.go:380: starting container process caused: error adding seccomp filter rule for syscall bdflush: requested action matches default action of filter`

启动时增加 `--security-opt seccomp=unconfined` 参数

+ podman启动访问后bind的目录提示 `Permission denied`

启动时增加 `--security-opt label=disable` 参数或关闭 selinux （修改 `/etc/selinux/config` 后重启）
