# dhcpd 注意事项

- 由于网络启动顺序和时间不定， `/lib/systemd/system/dhcpd4.service` 中请确保 `RestartSec` 和 `StartLimitInterval` 足够大。不然容器启动失败。

```conf
[Unit]
Description=IPv4 DHCP server
After=network.target network-online.target
Wants=network-online.target

[Service]
Type=forking
ExecStart=/usr/bin/dhcpd -4 -q -cf /etc/dhcpd.conf -pf /run/dhcpd4/dhcpd.pid
RuntimeDirectory=dhcpd4
PIDFile=/run/dhcpd4/dhcpd.pid
User=dhcp
AmbientCapabilities=CAP_NET_BIND_SERVICE CAP_NET_RAW
ProtectSystem=full
ProtectHome=on
KillSignal=SIGINT
# We pull in network-online.target for a configured network connection.
# However this is not guaranteed to be the network connection our
# networks are configured for. So try to restart on failure with a delay
# of 30 seconds. Rate limiting kicks in after 12 seconds.
RestartSec=30s
Restart=on-failure
StartLimitInterval=300s

[Install]
WantedBy=multi-user.target
```

 可以使用定时运行 `ip -o addr | grep "$ROUTER_INTERNAL_IPV4" > /dev/null && (systemctl -q status dhcpd4.service > /dev/null || systemctl start dhcpd4.service)` 来重试启动。
 上面的service配置容易被冲刷掉。

- 注意多个vlan时，要排除不需要的interface（subnet）

## KEA

<https://gitlab.isc.org/isc-projects/kea-docker>

## Docker内运行

- dhcpd/kea 需要监听 RAW 套接字来处理无源IP的DHCP广播，必须赋予相应权限。
  - CAP: NET_BIND_SERVICE, NET_RAW, NET_ADMIN , NET_BROADCAST。
  - rootless下无法赋予 NET_RAW ，所以dhcp服务必须在 rootful 模式下运行。
- DHCP 服务必须使用 `--network=host` 来管理原始 interface 。

## 测试

```bash
# 测试 DHCPv6 客户端请求
sudo dhclient -6 -v eth0

# 释放 DHCPv6 地址
sudo dhclient -6 -r eth0

# 指定配置文件测试
sudo dhclient -6 -cf /etc/dhcp/dhclient6.conf eth0
```
