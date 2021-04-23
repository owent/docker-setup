# Note

```bash
root@Lepton:/# ip rule s
0:      from all lookup 128
1:      from all lookup local
1001:   from all iif eth0 lookup main
1002:   from all iif eth1 lookup main
2001:   from all fwmark 0x100/0xff00 lookup 1
2002:   from all fwmark 0x200/0xff00 lookup 2
2254:   from all fwmark 0xfe00/0xff00 unreachable
32766:  from all lookup main
32767:  from all lookup default 

root@Lepton:/# ip route
default via 192.168.1.2 dev eth0  proto static  src 192.168.1.103
default via 172.16.8.1 dev eth1  proto static  src 172.16.8.121  metric 1
172.16.8.0/24 dev eth1  proto static  scope link  metric 1
172.16.8.1 dev eth1  proto static  scope link  src 172.16.8.121  metric 1
172.16.9.0/24 dev br-lan  proto kernel  scope link  src 172.16.9.2
192.168.1.0/24 dev eth0  proto kernel  scope link  src 192.168.1.103
192.168.1.2 dev eth0  proto static  scope link  src 192.168.1.103


```

```bash
root@Lepton:/# iptables -t mangle -L
Chain PREROUTING (policy ACCEPT)
target     prot opt source               destination
mwan3_hook  all  --  anywhere             anywhere

Chain OUTPUT (policy ACCEPT)
target     prot opt source               destination
mwan3_hook  all  --  anywhere             anywhere
mwan3_output_hook  all  --  anywhere             anywhere

Chain mwan3_connected (1 references)
target     prot opt source               destination
MARK       all  --  anywhere             127.0.0.0/8          MARK or 0xff00
MARK       all  --  anywhere             base-address.mcast.net/3  MARK or 0xff00
MARK       all  --  anywhere             172.16.8.0/24        MARK or 0xff00
MARK       all  --  anywhere             172.16.8.1           MARK or 0xff00
MARK       all  --  anywhere             172.16.9.0/24        MARK or 0xff00
MARK       all  --  anywhere             192.168.1.0/24       MARK or 0xff00
MARK       all  --  anywhere             192.168.1.2          MARK or 0xff00
MARK       all  --  anywhere             127.0.0.0            MARK or 0xff00
MARK       all  --  anywhere             127.0.0.0/8          MARK or 0xff00
MARK       all  --  anywhere             localhost            MARK or 0xff00
MARK       all  --  anywhere             127.255.255.255      MARK or 0xff00
MARK       all  --  anywhere             172.16.8.0           MARK or 0xff00
MARK       all  --  anywhere             172.16.8.121         MARK or 0xff00
MARK       all  --  anywhere             172.16.8.255         MARK or 0xff00
MARK       all  --  anywhere             172.16.9.0           MARK or 0xff00
MARK       all  --  anywhere             Lepton.lan           MARK or 0xff00
MARK       all  --  anywhere             172.16.9.255         MARK or 0xff00
MARK       all  --  anywhere             192.168.1.0          MARK or 0xff00
MARK       all  --  anywhere             192.168.1.103        MARK or 0xff00
MARK       all  --  anywhere             192.168.1.255        MARK or 0xff00

Chain mwan3_hook (2 references)
target     prot opt source               destination
CONNMARK   all  --  anywhere             anywhere             CONNMARK restore mask 0xff00
mwan3_ifaces  all  --  anywhere             anywhere             mark match 0x0/0xff00
mwan3_rules  all  --  anywhere             anywhere             mark match 0x0/0xff00
CONNMARK   all  --  anywhere             anywhere             CONNMARK save mask 0xff00
mwan3_connected  all  --  anywhere             anywhere

Chain mwan3_iface_wan (1 references)
target     prot opt source               destination
MARK       all  --  192.168.1.2          anywhere             mark match 0x0/0xff00 /* wan */ MARK or 0xff00
MARK       all  --  192.168.1.0/24       anywhere             mark match 0x0/0xff00 /* wan */ MARK or 0xff00
MARK       all  --  anywhere             anywhere             mark match 0x0/0xff00 /* wan */ MARK xset 0x100/0xff00

Chain mwan3_iface_wan1 (1 references)
target     prot opt source               destination
MARK       all  --  172.16.8.1           anywhere             mark match 0x0/0xff00 /* wan1 */ MARK or 0xff00
MARK       all  --  172.16.8.0/24        anywhere             mark match 0x0/0xff00 /* wan1 */ MARK or 0xff00
MARK       all  --  anywhere             anywhere             mark match 0x0/0xff00 /* wan1 */ MARK xset 0x200/0xff00

Chain mwan3_ifaces (1 references)
target     prot opt source               destination
mwan3_iface_wan  all  --  anywhere             anywhere             mark match 0x0/0xff00
mwan3_iface_wan1  all  --  anywhere             anywhere             mark match 0x0/0xff00

Chain mwan3_output_hook (1 references)
target     prot opt source               destination
mwan3_track_wan  icmp --  anywhere             anywhere             icmp echo-request length 32
mwan3_track_wan1  icmp --  anywhere             anywhere             icmp echo-request length 32

Chain mwan3_policy_balanced (1 references)
target     prot opt source               destination
MARK       all  --  anywhere             anywhere             mark match 0x0/0xff00 statistic mode random probability 0.50000000000 /* wan1 1 2 */ MARK xset 0x200/0xff00
MARK       all  --  anywhere             anywhere             mark match 0x0/0xff00 /* wan 1 1 */ MARK xset 0x100/0xff00

Chain mwan3_rules (1 references)
target     prot opt source               destination
mwan3_policy_balanced  all  --  anywhere             anywhere             mark match 0x0/0xff00 /* default_rule */

Chain mwan3_track_wan (1 references)
target     prot opt source               destination
MARK       all  --  anywhere             resolver2.opendns.com  MARK or 0xff00
MARK       all  --  anywhere             resolver1.opendns.com  MARK or 0xff00
MARK       all  --  anywhere             google-public-dns-a.google.com  MARK or 0xff00
MARK       all  --  anywhere             google-public-dns-b.google.com  MARK or 0xff00
MARK       all  --  anywhere             public1.114dns.com   MARK or 0xff00

Chain mwan3_track_wan1 (1 references)
target     prot opt source               destination
MARK       all  --  anywhere             resolver2.opendns.com  MARK or 0xff00
MARK       all  --  anywhere             google-public-dns-a.google.com  MARK or 0xff00
MARK       all  --  anywhere             public1.114dns.com   MARK or 0xff00 
```
