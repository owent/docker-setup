# 私有网络

## DNS支持（CNI）

`podman info --format {{.Host.NetworkBackend}}` 输出 cni 时。
`podman/docker info | grep network` 输出 networkBackend: cni 时有效。

1. 确认安装了依赖插件: `sudo apt install containernetworking-plugins golang-github-containernetworking-plugin-dnsname -y`
2. 确保 `/etc/cni/net.d/87-podman-bridge.conflist` 内包含 `dnsname` 和  。

```json
{
  "cniVersion": "0.4.0",
  "name": "podman",
  "plugins": [
    {
      "type": "bridge",
      "bridge": "cni-podman0",
      "isGateway": true,
      "ipMasq": true,
      "hairpinMode": true,
      "ipam": { 
        "type": "host-local",
        "routes": [{ "dst": "0.0.0.0/0" }],
        "ranges": [
          [
            {
              "subnet": "10.88.0.0/16",
              "gateway": "10.88.0.1"
            },
            // 增加ipv6配置
            {
              "subnet": "fd02:0:0:1:3::/96",
              "gateway": "fd02:0:0:1:3::1"
            }
          ]
        ]
      }
    },
    {
      "type": "portmap",
      "capabilities": { 
        "portMappings": true
      }
    },
    {
      "type": "firewall"
    },
    { 
      "type": "tuning"
    },
    {
      "type": "dnsname"
    }
  ]
}
```

## DNS支持（netavark）

`podman info --format {{.Host.NetworkBackend}}` 输出 netavark 时。
`podman/docker info | grep -i network` 输出 networkBackend: netavark 时。


如果本地网络监听了53端口，需要修改 `/etc/containers/containers.conf` 文件换端口。

```conf
[network]
dns_bind_port=1053
```

### Test DNS

- `podman run --network internal-backend --rm alpine nslookup unifi-db`
- `podman run --network internal-backend --pod <name> --rm alpine nslookup live-frontend`

> `podman run --network internal-backend --pod unifi-network-application`

### 查看特定网络中的容器

podman network inspect internal-backend | grep -A 20 -B 5 "containers"
podman inspect unifi-db | grep -A 10 -B 5 "Networks"
