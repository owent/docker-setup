# docker setup script

ENV:

+ SETUP_INSTALL_PROXY="http proxy"
+ SETUP_INSTALL_PREFIX
+ SETUP_WORK_DIR

## 启动命令备注

```bash
# 带systemd
podman run docker run -d --systemd true IMAGE /sbin/init
## systemd expects to have /run, /run/lock and /tmp on tmpfs
## It also expects to be able to write to /sys/fs/cgroup/systemd and /var/log/journal
## docker run -d --cap-add=SYS_ADMIN -v /sys/fs/cgroup:/sys/fs/cgroup IMAGE /sbin/init
## Mount list come from setupSystemd@libpod/container_internal_linux.go on https://github.com/containers/libpod
docker run -d --cap-add=SYS_ADMIN                                                           \
        --mount type=tmpfs,target=/run,tmpfs-mode=1777,tmpfs-size=67108864                  \
        --mount type=tmpfs,target=/run/lock,tmpfs-mode=1777,tmpfs-size=67108864             \
        --mount type=tmpfs,target=/tmp,tmpfs-mode=1777                                      \
        --mount type=tmpfs,target=/var/log/journal,tmpfs-mode=1777                          \
        --mount type=bind,source=/sys/fs/cgroup,target=/sys/fs/cgroup                       \
        IMAGE /sbin/init
        # --mount type=bind,source=/sys/fs/cgroup/systemd,target=/sys/fs/cgroup/systemd

# 路由
podman build --tag router-base -f debian10.router.raw.Dockerfile
podman run -d --systemd true --mount type=bind,source=/home,target=/home --cap-add=NET_ADMIN --network=host IMAGE /sbin/init

# @see https://docs.docker.com/engine/reference/builder/#entrypoint for detail about CMD and ENTRYPOINT

# 查看当前内核所有可用的模块
find /lib/modules/$(uname -r) -type f -name '*.ko*' | xargs basename -a | sort | uniq

# 查看已安装的内核所有可用的模块
find /lib/modules/ -type f -name '*.ko*' | awk '{if (match($0, /^\/lib\/modules\/([^\/]+).*\/([^\/]+)\.ko(\.[^\/\.]+)?$/, m)) {print m[1] " : " m[2];}}' | sort | uniq
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
