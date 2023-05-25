# dhcpd 注意事项

+ 由于网络启动顺序和时间不定， `/lib/systemd/system/dhcpd4.service` 中请确保 `RestartSec` 和 `StartLimitInterval` 猪狗大。不然容器启动失败。

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

+ 注意多个vlan时，要排除不需要的interface（subnet）
