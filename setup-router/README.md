# README for router

## Host machine

Lan bridge:  br0
> enp1s0f0, enp1s0f1, enp5s0

Wan: enp1s0f2, enp1s0f3
> Disable auto start

```bash
# Make sure iptable_nat is not loaded, @see https://wiki.nftables.org/wiki-nftables/index.php/Performing_Network_Address_Translation_(NAT)#Incompatibilities
# Install iptables-nft to replace dependencies to iptables of some packages
echo "## Do not load the iptable_nat,ip_tables,ip6table_nat,ip6_tables module on boot.
blacklist iptable_nat
blacklist ip_tables
blacklist ip6table_nat
blacklist ip6_tables

# Upper script will disable auto load , or using scripts below to force disable modules
# install iptable_nat /bin/true
# install ip_tables /bin/true
# install ip6table_nat /bin/true
# install ip6_tables /bin/true
" | tee /etc/modprobe.d/disable-iptables.conf


cp -f kernel-modules-tproxy.conf /etc/modules-load.d/tproxy.conf ;
cp -f kernel-modules-ppp.conf /etc/modules-load.d/ppp.conf ;

for MOD_FOR_ROUTER in $(cat /etc/modules-load.d/tproxy.conf); do
    modprobe $MOD_FOR_ROUTER;
done

# iptable_nat must not be loaded
for MOD_FOR_ROUTER in $(cat /etc/modules-load.d/ppp.conf); do
    modprobe $MOD_FOR_ROUTER;
done

echo "
net.core.rmem_default = 1048576
net.core.rmem_max = 16777216
net.core.wmem_default = 1048576
net.core.wmem_max = 16777216
net.core.optmem_max = 65536
net.ipv4.tcp_rmem = 4096 1048576 2097152
net.ipv4.tcp_wmem = 4096 65536 16777216
net.ipv4.udp_rmem_min = 8192
net.ipv4.udp_wmem_min = 8192
net.ipv4.tcp_mtu_probing=1
net.ipv4.tcp_syncookies=1
net.ipv4.tcp_tw_reuse=1
net.ipv4.tcp_fin_timeout=10
net.ipv4.tcp_fastopen=3
net.ipv4.tcp_max_syn_backlog=30000
net.ipv4.tcp_max_tw_buckets=2000000
net.ipv4.tcp_keepalive_time = 150
net.ipv4.tcp_keepalive_intvl = 75
net.ipv4.tcp_keepalive_probes = 6
net.ipv4.ip_forward=1
net.ipv4.ip_forward_use_pmtu=1
net.ipv4.conf.all.forwarding=1
net.ipv4.conf.default.forwarding=1
net.ipv6.conf.all.forwarding=1
net.ipv6.conf.default.forwarding=1
net.ipv6.conf.all.accept_ra=1
net.ipv6.conf.default.accept_ra=1
" > /etc/sysctl.d/91-forwarding.conf ;
sysctl -p ;

# Check and enable bbr
find /lib/modules/ -type f -name '*.ko*' | awk '{if (match($0, /^\/lib\/modules\/([^\/]+).*\/([^\/]+)\.ko(\.[^\/\.]+)?$/, m)) {print m[1] " : " m[2];}}' | sort | uniq | grep tcp_bbr ;
if [ $? -eq 0 ]; then
    modprobe tcp_bbr ;
    if [ $? -eq 0 ]; then
        sed -i "/tcp_bbr/d" /etc/modules-load.d/*.conf ;
        sed -i "/net.core.default_qdisc/d" /etc/sysctl.d/*.conf;
        sed -i "/net.ipv4.tcp_congestion_control/d" /etc/sysctl.d/*.conf;
        echo "tcp_bbr" >> /etc/modules-load.d/ppp.conf ;
        echo "net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr" >> /etc/sysctl.d/91-forwarding.conf ;
    fi
fi


# systemd-resolved will listen 53 and will conflict with our dnsmasq.service
sed -i -r 's/#?DNSStubListener[[:space:]]*=.*/DNSStubListener=no/g'  /etc/systemd/resolved.conf ;

systemctl disable systemd-resolved ;
systemctl stop systemd-resolved ;

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
```

## ip route

```bash
while [ ! -z "$(ip route show default 2>/dev/null)" ]; do
    ip route delete default ;
done
# ip route add default via XXX dev ppp0 ;
ip route add default dev ppp0 ;
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
