# README for router

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
" | tee /etc/modprobe.d/disable-iptables.conf

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
## ================= Untest =================
# Disable local-link address for internal bridge(For IPv6 NAT)
net.ipv6.conf.br0.forwarding=1
net.ipv6.conf.br0.proxy_ndp=1
net.ipv6.conf.br0.accept_ra=2
# For all other interfaces set these 3 options
" | sudo tee /etc/sysctl.d/91-forwarding.conf ;

echo "net.ipv4.ip_unprivileged_port_start=67
kernel.unprivileged_userns_clone=1
user.max_user_namespaces=28633
" | sudo tee /etc/sysctl.d/92-container.conf ;

sysctl -p ;

# Check and enable bbr
find /lib/modules/ -type f -name '*.ko*' | awk '{if (match($0, /^\/lib\/modules\/([^\/]+).*\/([^\/]+)\.ko(\.[^\/\.]+)?$/, m)) {print m[1] " : " m[2];}}' | sort | uniq | grep tcp_bbr ;
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
```bash
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

# systemd-resolved will listen 53 and will conflict with our dnsmasq.service/smartdns.service
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

|  Type  |       Families          |      Hooks                             |        Description                                     |
|--------|-------------------------|----------------------------------------|--------------------------------------------------------|
| filter | all                     | all                                    | Standard chain type to use in doubt.                   |
| nat    | ip, ip6, inet           | prerouting, input, output, postrouting | Chains of this type perform Native Address Translation based on conntrack entries. Only the first packet of a connection actually traverses this chain - its rules usually define details of the created conntrack entry (NAT statements for instance). |
| route  | ip, ip6                 | output                                 | If a packet has traversed a chain of this type and is about to be accepted, a new route lookup is performed if relevant parts of the IP header have changed. This allows to e.g. implement policy routing selectors in nftables. |

## Standard priority names, family and hook compatibility matrix

> The priority parameter accepts a signed integer value or a standard priority name which specifies the order in which chains with same hook value are traversed. The ordering is ascending, i.e. lower priority values have precedence over higher ones.

| Name      | Value | Families                   | Hooks       |
|-----------|-------|----------------------------|-------------|
| raw       | -300  | ip, ip6, inet              | all         |
| mangle    | -150  | ip, ip6, inet              | all         |
| dstnat    | -100  | ip, ip6, inet              | prerouting  |
| filter    | 0     | ip, ip6, inet, arp, netdev | all         |
| security  | 50    | ip, ip6, inet              | all         |
| srcnat    | 100   | ip, ip6, inet              | postrouting |

## Standard priority names and hook compatibility for the bridge family

|Name   | Value | Hooks       |
|-------|-------|-------------|
|dstnat | -300  | prerouting  |
|filter | -200  | all         |
|out    | 100   | output      |
|srcnat | 300   | postrouting |

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

## Podman/docker 存储设置

### podman 存储

文件: `/etc/containers/storage.conf` 或 `$HOME/.config/containers/storage.conf`

```toml
[storage]
  driver = "overlay"
  runroot = "/data/docker-container"
  graphroot = "/data/docker-image"
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

[1]: https://tools.ietf.org/html/rfc8484 "RFC 8484"
[2]: https://tools.ietf.org/html/rfc7858 "RFC 7858"
[3]: https://dnscrypt.info/ "DNSCrypt"
[4]: https://datatracker.ietf.org/doc/draft-ietf-dprive-dnsoquic/ "DNS over Dedicated QUIC Connections(Draft)"

