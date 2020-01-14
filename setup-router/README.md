# README for router

## host machine

Lan bridge: br0: enp1s0f0, enp1s0f1, enp5s0
Wan: enp1s0f2, enp1s0f3

```bash
# Make sure iptable_nat is not loaded, @see https://wiki.nftables.org/wiki-nftables/index.php/Performing_Network_Address_Translation_(NAT)#Incompatibilities
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


cp -f kernel-modules-tproxy.conf /etc/modules-load.d/tproxy.conf
cp -f kernel-modules-ppp.conf /etc/modules-load.d/ppp.conf

for MOD_FOR_ROUTER in $(cat /etc/modules-load.d/tproxy.conf); do
    modprobe $MOD_FOR_ROUTER;
done

# iptable_nat must not be loaded
for MOD_FOR_ROUTER in $(cat /etc/modules-load.d/ppp.conf); do
    modprobe $MOD_FOR_ROUTER;
done

echo "
net.ipv4.ip_forward=1
net.ipv4.conf.all.forwarding=1
net.ipv4.conf.default.forwarding=1
net.ipv6.conf.all.forwarding=1
net.ipv6.conf.default.forwarding=1
" > /etc/sysctl.d/91-forwarding.conf ;
sysctl -p ;

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
