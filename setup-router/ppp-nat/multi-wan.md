# Note for mwan

## PPP scripts(TODO)

```bash
PPP_IF_INDEX=$(echo "$IFNAME" | grep -E -o '[0-9]+$');
MAX_RETRY_TIMES=32;
let PPP_ROUTE_TABLE_ID=121+$PPP_IF_INDEX;
let PPP_RULE_IF_PRIORITY=$PPP_ROUTE_TABLE_ID*100;
let PPP_RULE_POLICY_PRIORITY=$PPP_RULE_IF_PRIORITY+10000;
```

### ppp up

```bash
export PATH=$PATH:/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin:$HOME/bin:$HOME/.local/bin
mkdir -p /run/multi-wan/ ;

sed -i "/^$IFNAME\\b/d" /run/multi-wan/ipv4 ;
echo "$IFNAME DEVICE=\"$DEVICE\" IPLOCAL=\"$IPLOCAL\" IPREMOTE=\"$IPREMOTE\" PEERNAME=\"$PEERNAME\" SPEED=\"$SPEED\" LINKNAME=\"$LINKNAME\"" >> /run/multi-wan/ipv4 ;
for RECHECK_PPP_IF in $(cat /run/multi-wan/ipv4 | awk '{print $1}'); do
  ip -4 -o addr show dev $CHECK_PPP_IF ;
  if [[ $? -ne 0 ]]; then
    sed -i "/^$RECHECK_PPP_IF\\b/d" /run/multi-wan/ipv4 ;
  fi
done
```

1. add named route table `$PPP_ROUTE_TABLE_ID` into `/etc/iproute2/rt_tables` when ppp up
2. `ip -4 rule add iif $IFNAME priority $PPP_RULE_IF_PRIORITY lookup main`
3. `ip -4 rule add fwmark 0x${PPP_IF_INDEX}00/0xff00 priority $PPP_RULE_POLICY_PRIORITY lookup main suppress_prefixlength 0`
4. `ip -4 rule add fwmark 0x${PPP_IF_INDEX}00/0xff00 priority $PPP_RULE_POLICY_PRIORITY lookup $PPP_ROUTE_TABLE_ID`
5. `nft add chain inet mwan MARK_PPP_${PPP_IF_INDEX}`
6. `nft add rule inet mwan MARK_PPP_${PPP_IF_INDEX} meta mark and 0xff00 == 0x0 ip saddr $IPLOCAL meta mark set meta mark and 0xffff00ff xor 0xff00`
7. `nft add rule inet mwan MARK_PPP_${PPP_IF_INDEX} meta mark and 0xff00 == 0x0 ip saddr $IPREMOTE meta mark set meta mark and 0xffff00ff xor 0xff00`
8. `nft add rule inet mwan MARK meta mark & 0xff00 == 0x0000 jump MARK_PPP_${PPP_IF_INDEX}`
9. Patch Balance Rule `MARK_BALANCE` : (insert top, reset `$SUM_WEIGHT`)

### ppp down

```bash
export PATH=$PATH:/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin:$HOME/bin:$HOME/.local/bin

if [[ -e "/run/multi-wan/ipv4" ]]; then
  sed -i "/^$IFNAME\\b/d" /run/multi-wan/ipv4 ;
fi
```

1. remove named route table `$PPP_ROUTE_TABLE_ID` into /etc/iproute2/rt_tables when ppp up
2. `ip -4 rule delete iif $IFNAME lookup main`
3. `ip -4 rule delete fwmark 0x${PPP_IF_INDEX}00/0xff00 lookup main`
4. `ip -4 rule delete fwmark 0x${PPP_IF_INDEX}00/0xff00 lookup $PPP_ROUTE_TABLE_ID`
5. Remove `MARK_PPP_${PPP_IF_INDEX}` from `MARK`
  >
  > ```bash
  > HANDLE_ID=$(nft -a list chain inet mwan MARK | grep -E -i "jump[[:space:]]+MARK_PPP_${PPP_IF_INDEX}" | grep -E -i "#[[:space:]]*handle[[:space:]]*.*$" | awk '{print $NF}') ;
  > nft delete rule inet mwan MARK handle $HANDLE_ID ;
  > ```
  >
6. `nft delete chain inet mwan MARK_PPP_${PPP_IF_INDEX}`
7. Patch Balance rule `MARK_BALANCE`

### Patch Balance Rule

> `nft insert rule inet mwan MARK_BALANCE index 0 meta mark & 0xff00 == 0x0000 symhash mod $SUM_WEIGHT 0 meta mark set meta mark and 0xffff00ff xor 0x${PPP_IF_INDEX}00`
> `nft delete rule inet mwan MARK_BALANCE handle HANDLE`

```bash
eval "ALL_RULES=($(nft list chain inet mwan MARK_BALANCE | grep -E -i "numgen|symhash|jhash" | awk '{sub(/^[[:space:]]+/, "");print "\""$0"\""}'))";
for RULE in "${ALL_RULES[@]}"; do
  echo "RULE: $RULE";
done
```

## ip rule and ip route

```bash
$ ip rule
0:      from all lookup local
7100:   from all iif ppp0 lookup main
7101:   from all iif ppp1 lookup main
23001:  from all fwmark 0x200/0xff00 lookup main suppress_prefixlength 0
23002:  from all fwmark 0x200/0xff00 lookup 101
29991:  from all fwmark 0xe/0xf lookup 100
32766:  from all lookup main
32767:  from all lookup default

$ ip route show table main         
default via 114.95.200.1 dev ppp1 proto static metric 101 
default via 10.64.255.254 dev ppp0 proto static metric 104 
10.64.255.254 dev ppp0 proto kernel scope link src 10.64.177.190 metric 109 
114.95.200.1 dev ppp1 proto kernel scope link src 114.95.201.4 metric 108 
172.18.0.0/16 dev br0 proto kernel scope link src 172.18.1.10 metric 425 
172.20.0.0/16 dev br0 proto kernel scope link src 172.20.1.1 metric 425

$ ip route show table 101 
default via 10.64.255.254 dev ppp0 proto static metric 104
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
    meta mark & 0x0000ff00 == 0x00000000 meta mark set ct mark & 0x0000ffff
    meta mark & 0x0000ff00 != 0x00000000 return
    ip daddr { 127.0.0.1, 224.0.0.0/4, 255.255.255.255 } return
    ip daddr { 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16 } return
    ip daddr { 119.29.29.29, 180.76.76.76, 223.5.5.5, 223.6.6.6 } return
    ip6 daddr { ::1, fc00::/7, fe80::/10, ff00::-ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff } return
    ip6 daddr { 2400:3200::1, 2400:3200:baba::1, 2400:da00::6666 } return
    meta mark & 0x0000ff00 == 0x00000000 ip saddr 114.95.201.4 meta mark set meta mark | 0x0000ff00
    meta mark & 0x0000ff00 == 0x00000000 ip saddr 114.95.200.1 meta mark set meta mark | 0x0000ff00
    meta mark & 0x0000ff00 == 0x00000000 ip saddr 10.64.177.190 meta mark set meta mark | 0x0000ff00
    meta mark & 0x0000ff00 == 0x00000000 ip saddr 10.64.255.254 meta mark set meta mark | 0x0000ff00
    meta mark & 0x0000ff00 == 0x00000000 symhash mod 4 0 meta mark set meta mark & 0xffff02ff | 0x00000200
    meta mark & 0x0000ff00 == 0x00000000 meta mark set meta mark & 0xfffffeff | 0x0000fe00
    ct mark set meta mark & 0x0000ffff
  }
}
```
