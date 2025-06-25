# Note for mwan

## ip rule and ip route

```bash
$ ip rule
0:      from all lookup local
1:      from all lookup local
7100:   from all iif ppp0 lookup main
7101:   from all iif enp1s0f2 lookup main
17995:  from all fwmark 0xe/0xf lookup 100
23001:  from all fwmark 0x100/0xff00 lookup main suppress_prefixlength 0
23002:  from all fwmark 0x100/0xff00 lookup 121
23003:  from all fwmark 0x200/0xff00 lookup main suppress_prefixlength 0
23004:  from all fwmark 0x200/0xff00 lookup 122
32766:  from all lookup main
32767:  from all lookup default

$ ip route show table main
default via 100.65.0.1 dev ppp0 proto static metric 102 
default via 192.168.1.1 dev enp1s0f2 proto dhcp metric 104 
100.65.0.1 dev ppp0 proto kernel scope link src 100.65.1.219 metric 105 
172.18.0.0/16 dev br0 proto kernel scope link src 172.18.1.10 metric 425 
172.20.0.0/16 dev br0 proto kernel scope link src 172.20.1.1 metric 425 
192.168.1.0/24 dev enp1s0f2 proto kernel scope link src 192.168.1.3 metric 104

$ ip route show table 121 
default via 192.168.1.1 dev enp1s0f2 proto dhcp metric 104

$ ip route show table 122
default via 100.65.0.1 dev ppp0 proto static metric 102
```

## nftables

```bash
$ sudo nft list table inet mwan
table inet mwan {
  chain PREROUTING {
    type filter hook prerouting priority mangle; policy accept;
    jump MARK
  }

  chain OUTPUT {
    type route hook output priority mangle; policy accept;
    jump MARK
  }

  chain MARK {
    meta l4proto != { tcp, udp } return
    meta mark & 0x0000ff00 != 0x00000000 return
    meta mark & 0x0000ffff != 0x00000000 ct mark & 0x0000ff00 == 0x00000000 ct mark set meta mark & 0x0000ffff
    meta mark & 0x0000ff00 == 0x00000000 ct mark & 0x0000ff00 != 0x00000000 meta mark set ct mark & 0x0000ffff
    meta mark & 0x0000ff00 != 0x00000000 return
    ip daddr { 127.0.0.1, 224.0.0.0/4, 255.255.255.255 } return
    ip daddr { 0.0.0.0/8, 10.0.0.0/8, 127.0.0.0/8, 169.254.0.0/16, 172.16.0.0/12, 192.0.0.0/24, 192.168.0.0/16, 224.0.0.0/4, 240.0.0.0/4 } return
    ip daddr { 119.29.29.29, 180.76.76.76, 223.5.5.5, 223.6.6.6, 1.12.12.12, 120.53.53.53, 1.1.1.1, 1.0.0.1, 8.8.8.8, 8.8.4.4 } return
    ip6 daddr { ::1, fc00::/7, fe80::/10, ff00::-ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff } return
    ip6 daddr { 2400:3200::1, 2400:3200:baba::1, 2400:da00::6666, 2402:4e00::, 2606:4700:4700::1111, 2606:4700:4700::1001, 2606:4700:4700::1111, 2606:4700:4700::1001 } return
    meta mark & 0x0000ff00 == 0x00000000 ip saddr 192.168.1.3 meta mark set meta mark | 0x0000ff00
    meta mark & 0x0000ff00 == 0x00000000 ip saddr 100.65.1.219 meta mark set meta mark | 0x0000ff00
    meta mark & 0x0000ff00 == 0x00000000 jump POLICY_MARK
    meta mark & 0x0000ff00 == 0x00000000 meta mark set meta mark & 0xfffffeff | 0x0000fe00
    ct mark set meta mark & 0x0000ffff
  }

  chain POLICY_MARK {
    meta mark & 0x0000ff00 == 0x00000000 symhash mod 6 < 5 meta mark set meta mark & 0xffff01ff | 0x00000100 return
    meta mark & 0x0000ff00 == 0x00000000 meta mark set meta mark & 0xffff02ff | 0x00000200 return
  }
}
```
