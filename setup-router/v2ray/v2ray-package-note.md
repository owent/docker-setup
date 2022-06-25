# 包转发流程记录

所有的地址都指传输层地址5元组： ```(协议,源地址,源端口,目的地址,目的端口)```

## 经过v2ray代理的流量

**PPP地址1**和**PPP地址2**的IP相同，端口+协议不同。

出站包请求流程:

1. **原始内网地址**->**原始外网地址** (from:LAN)
2. REDIRECT/TPROXY(DNAT): **PPP地址1**->**原始外网地址** (命中转发规则，转发给 V2RAY listen地址) - [xtable][2]
  > R1: DNAT规则: **原始内网地址**->**原始外网地址**    => **PPP地址1**->**原始外网地址**
  > R2: DNAT规则: **原始外网地址**->**PPP地址1**        => **原始外网地址**->**原始内网地址**

3. V2RAY封包: **V2RAY-CLI地址**->**V2RAY-SVR地址** - 应用层v2ray服务
  > R3: NAT规则: **PPP地址1**->**原始外网地址**         => **V2RAY-CLI地址**->**V2RAY-SVR地址**
  > R4: NAT规则: **V2RAY-SVR地址**->**V2RAY-CLI地址**   => **原始外网地址**->**PPP地址1**

4. SNAT: **PPP地址2**->**V2RAY-SVR地址** (不命中转发规则， 走到后面的NAT链, ```white_list``` 包含 **V2RAY-SVR地址** 的IP/或根据mark判定 ) - [xtable][2]
  > R5: SNAT规则: **V2RAY-CLI地址**->**V2RAY-SVR地址**  => **PPP地址2**->**V2RAY-SVR地址**
  > R6: SNAT规则: **V2RAY-SVR地址**->**PPP地址2**       => **V2RAY-SVR地址**->**V2RAY-CLI地址**

入站包请求流程:

1. **V2RAY-SVR地址**->**PPP地址2**  (不命中转发规则, ```white_list``` 包含 **PPP地址2** 的IP)
2. SNAT-R6: **V2RAY-SVR地址**->**V2RAY-CLI地址**  (不命中转发规则, ```white_list``` 包含内网地址 **V2RAY-CLI地址** 是内网地址) - [xtable][2]
3. V2RAY-R4解包: **原始外网地址**->**PPP地址1**  (不命中转发规则, ```white_list``` 包含 **PPP地址1** 的IP) - 应用层v2ray服务
4. DNAT-R2: **原始外网地址**->**原始内网地址** (不命中转发规则, ```white_list``` 包含内网地址) - [xtable][2]

## 不经过v2ray代理的流量（不经过v2ray服务）

**PPP地址1**和**PPP地址2**的IP相同，端口+协议不同。

出站包请求流程:

1. **原始内网地址**->**原始外网地址** (from:LAN)
2. SNAT: **PPP地址1**->**原始外网地址** (不命中转发规则) - [xtable][2]
  > R1: DNAT规则: **原始内网地址**->**原始外网地址**    => **PPP地址1**->**原始外网地址**
  > R2: DNAT规则: **原始外网地址**->**PPP地址1**        => **原始外网地址**->**原始内网地址**

入站包请求流程:

1. **原始外网地址**->**PPP地址1**  (不命中转发规则, ```white_list``` 包含 **PPP地址1** 的IP)
2. SNAT-R2: **原始外网地址**->**原始内网地址**  (不命中转发规则, ```white_list``` 包含内网地址) - [xtable][2]


## 不经过v2ray代理的流量（经过v2ray服务）

**PPP地址1**和**PPP地址2**的IP相同，端口+协议不同。

出站包请求流程:

1. **原始内网地址**->**原始外网地址** (from:LAN)
2. REDIRECT/TPROXY(DNAT): **PPP地址1**->**原始外网地址** (命中转发规则，转发给 V2RAY listen地址) - [xtable][2]
  > R1: DNAT规则: **原始内网地址**->**原始外网地址**    => **PPP地址1**->**原始外网地址**
  > R2: DNAT规则: **原始外网地址**->**PPP地址1**        => **原始外网地址**->**原始内网地址**

3. V2RAY透明转发: **V2RAY-CLI地址**->**原始外网地址** - 应用层v2ray服务
  > R3: NAT规则: **PPP地址1**->**原始外网地址**         => **V2RAY-CLI地址**->**原始外网地址**
  > R4: NAT规则: **原始外网地址**->**V2RAY-CLI地址**   => **原始外网地址**->**PPP地址1**

4. SNAT: **PPP地址2**->**原始外网地址** (不命中转发规则， 走到后面的NAT链, mark规则排除) - [xtable][2]
  > R5: SNAT规则: **V2RAY-CLI地址**->**原始外网地址**  => **PPP地址2**->**原始外网地址**
  > R6: SNAT规则: **原始外网地址**->**PPP地址2**       => **原始外网地址**->**V2RAY-CLI地址**

入站包请求流程:

1. **原始外网地址**->**PPP地址2**  (不命中转发规则, ```white_list``` 包含 **PPP地址2** 的IP)
2. SNAT-R6: **原始外网地址**->**V2RAY-CLI地址**  (不命中转发规则, ```white_list``` 包含内网地址 **V2RAY-CLI地址** 是内网地址) - [xtable][2]
3. V2RAY-R4: **原始外网地址**->**PPP地址1**  (不命中转发规则, ```white_list``` 包含 **PPP地址1** 的IP) - 应用层v2ray服务
4. DNAT-R2: **原始外网地址**->**原始内网地址** (不命中转发规则, ```white_list``` 包含内网地址) - [xtable][2]

## 实时更新

需要实时更新 **V2RAY-SVR地址** 的IP 和 **PPP地址** 的IP 到 [ipset][2] 的 ```white_list``` 。

[1]: http://ipset.netfilter.org/
[2]: https://nftables.org/