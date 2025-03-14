# K3S

[k3s.io](https://k3s.io/)

## 初始化

### 开放端口

| Protocol | Port      | Source    | Destination | Description                                              |
| -------- | --------- | --------- | ----------- | -------------------------------------------------------- |
| TCP      | 2379-2380 | Servers   | Servers     | Required only for HA with embedded etcd                  |
| TCP      | 6443      | Agents    | Servers     | K3s supervisor and Kubernetes API Server                 |
| UDP      | 8472      | All nodes | All nodes   | Required only for Flannel VXLAN                          |
| TCP      | 10250     | All nodes | All nodes   | Kubelet metrics                                          |
| UDP      | 51820     | All nodes | All nodes   | Required only for Flannel Wireguard with IPv4            |
| UDP      | 51821     | All nodes | All nodes   | Required only for Flannel Wireguard with IPv6            |
| TCP      | 5001      | All nodes | All nodes   | Required only for embedded distributed registry (Spegel) |
| TCP      | 6443      | All nodes | All nodes   | Required only for embedded distributed registry (Spegel) |

### 特权

+ NET_RAW : Flannel relies on the Bridge CNI plugin to create a L2 network that switches traffic.

### Rootless server准备

+ 启用 [cgroup v2](https://rootlesscontaine.rs/getting-started/common/cgroup2/)

## 环境变和设置

文档: <https://docs.k3s.io/zh/installation/configuration>

| 环境变量                        | 描述                                                                                                                                                         |
| ------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `INSTALL_K3S_SKIP_DOWNLOAD`     | 如果设置为 `true` 将不会下载 K3s 哈希或二进制文件。                                                                                                          |
| `INSTALL_K3S_SYMLINK`           | 默认情况下，如果命令不存在于路径中，将为 kubectl、crictl 和 ctr 二进制文件创建符号链接。如果设置为 `skip` 将不会创建符号链接，设置为 `force` 将会覆盖。      |
| `INSTALL_K3S_SKIP_ENABLE`       | 如果设置为 `true` 将不会启用或启动 K3s 服务。                                                                                                                |
| `INSTALL_K3S_SKIP_START`        | 如果设置为 `true` 将不会启动 K3s 服务。                                                                                                                      |
| `INSTALL_K3S_VERSION`           | 从 GitHub 下载的 K3s 版本。如果未指定，将尝试从 stable channel 下载。                                                                                        |
| `INSTALL_K3S_BIN_DIR`           | 安装 K3s 二进制文件、链接和卸载脚本的目录，或使用 `/usr/local/bin` 作为默认目录。                                                                            |
| `INSTALL_K3S_BIN_DIR_READ_ONLY` | 如果设置为 `true` 将不会将文件写入 `INSTALL_K3S_BIN_DIR`，强制设置为 `INSTALL_K3S_SKIP_DOWNLOAD=true`。                                                      |
| `INSTALL_K3S_SYSTEMD_DIR`       | 安装 systemd 服务和环境文件的目录，或使用 `/etc/systemd/system` 作为默认目录。                                                                               |
| `INSTALL_K3S_EXEC`              | 带有标志的命令，用于在服务中启动 K3s。如果未指定命令并且设置了 `K3S_URL`，它将默认为 "agent"。如果未设置 `K3S_URL`，它将默认为 "server"。                    |
| `INSTALL_K3S_NAME`              | 要创建的 systemd 服务的名称，如果将 K3s 作为 server 运行，则默认为 “k3s”，如果将 K3s 作为 agent 运行，则默认为 “k3s-agent”。如果指定，名称将以“k3s-”为前缀。 |
| `INSTALL_K3S_TYPE`              | 要创建的 systemd 服务类型，如果未指定，将默认使用来自 K3s exec 命令的类型。                                                                                  |
| `INSTALL_K3S_SELINUX_WARN`      | 如果设置为 `true`，则在未找到 k3s-selinux 策略时会继续。                                                                                                     |
| `INSTALL_K3S_SKIP_SELINUX_RPM`  | 如果设置为 `true` 将跳过 k3s RPM 的自动安装。                                                                                                                |
| `INSTALL_K3S_CHANNEL_URL`       | 用于获取 K3s 下载 URL 的 Channel URL。默认为 https://update.k3s.io/v1-release/channels。                                                                     |
| `INSTALL_K3S_CHANNEL`           | 用于获取 K3s 下载 URL 的 Channel。默认为 "stable"。可选项：`stable`、`latest`、`testing`。                                                                   |
| `SERVER_EXTERNAL_IP`            | Server的外网IP。                                                                                                                                             |
| `AGENT_EXTERNAL_IP`             | Agent的外网IP。                                                                                                                                              |

代理环境变量:

```bash
# 全局
HTTP_PROXY=http://your-proxy.example.com:8888
HTTPS_PROXY=http://your-proxy.example.com:8888
NO_PROXY=127.0.0.0/8,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16

# 仅对 containerd 生效
CONTAINERD_HTTP_PROXY=http://your-proxy.example.com:8888
CONTAINERD_HTTPS_PROXY=http://your-proxy.example.com:8888
CONTAINERD_NO_PROXY=127.0.0.0/8,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16
```

### 服务器启动

服务器启动选项: <https://docs.k3s.io/zh/cli/server>

重要选项和注意事项:

+ `--cluster-cidr=10.42.0.0/16,2001:cafe:42::/56` : CIDR每个节点不能冲突。用于 pod IP 的 IPv4/IPv6 网络 CIDR。
+ `--service-cidr=10.43.0.0/16,2001:cafe:43::/112` : 用于服务 IP 的 IPv4/IPv6 网络 CIDR
+ `--node-external-ip=<SERVER_EXTERNAL_IP>` : 外网IP
+ `--cluster-domain=cluster.local` : 集群域名
+ `--tls-san=hostname` : 在 TLS 证书上添加其他主机名或 IPv4/IPv6 地址作为 Subject Alternative Name
+ `--config FILE, -c FILE` : 配置路径(/etc/rancher/k3s/config.yaml), `$K3S_CONFIG_FILE`

服务器示例:

```bash
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server" sh -s - --flannel-backend none --token 12345
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server --flannel-backend none" K3S_TOKEN=12345 sh -s -
curl -sfL https://get.k3s.io | K3S_TOKEN=12345 sh -s - server --flannel-backend none
# server is assumed below because there is no K3S_URL
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--flannel-backend none --token 12345" sh -s - 
curl -sfL https://get.k3s.io | sh -s - --flannel-backend none --token 12345
```

#### 启动集群(HA,etcd)

第一台:

```bash
curl -sfL https://get.k3s.io | K3S_TOKEN=SECRET sh -s - server \
    --cluster-init \
    --tls-san=<FIXED_IP> # Optional, needed if using a fixed registration address
```

后续加入

```bash
curl -sfL https://get.k3s.io | K3S_TOKEN=SECRET sh -s - server \
    --server https://<ip or hostname of server1>:6443 \
    --tls-san=<FIXED_IP> # Optional, needed if using a fixed registration address
```

#### 启动集群(HA,外部数据库)

启动Server节点:

```bash
curl -sfL https://get.k3s.io | sh -s - server \
  --token=SECRET \
  --datastore-endpoint="mysql://username:password@tcp(hostname:3306)/database-name"
  --tls-san=<FIXED_IP> # Optional, needed if using a fixed registration address
```

可用的数据库选项:

+ PostgreSQL: `postgres://username:password@hostname:port/database-name`
+ MySQL: `mysql://username:password@tcp(hostname:3306)/database-name`
+ etcd: `https://etcd-host-1:2379,https://etcd-host-2:2379,https://etcd-host-3:2379`

添加其他节点:

```bash
curl -sfL https://get.k3s.io | sh -s - server \
  --token=SECRET \
  --datastore-endpoint="mysql://username:password@tcp(hostname:3306)/database-name"

# For CN
curl -sfL https://rancher-mirror.rancher.cn/k3s/k3s-install.sh | INSTALL_K3S_MIRROR=cn sh -s - server \
  --token=SECRET \
  --datastore-endpoint="mysql://username:password@tcp(hostname:3306)/database-name"
```

添加Agent:

```bash
K3S_TOKEN=SECRET k3s agent --server https://server-or-fixed-registration-address:6443
```

特殊选项:

+ `--node-taint CriticalAddonsOnly=true:NoExecute` ： 污点，不会运行用户工作负载

### agent启动

agent启动选项: <https://docs.k3s.io/zh/cli/agent>

agent示例:

```bash
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="agent --server https://k3s.example.com --token mypassword" sh -s -
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="agent" K3S_TOKEN="mypassword" sh -s - --server https://k3s.example.com
curl -sfL https://get.k3s.io | K3S_URL=https://k3s.example.com sh -s - agent --token mypassword
curl -sfL https://get.k3s.io | K3S_URL=https://k3s.example.com K3S_TOKEN=mypassword sh -s - # agent is assumed because of K3S_URL
```
