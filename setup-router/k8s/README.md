# Kubernetes

## 系统环境准备

```bash
# 依赖包
sudo apt install -y sudo openssl curl socat conntrack ebtables ipset ipvsadm ethtool chrony ndisc6 sysstat
sudo systemctl enable chrony --now
sudo systemctl disable dnsmasq
sudo systemctl stop dnsmasq
sudo systemctl stop systemd-resolved
sudo systemctl disable systemd-resolved

# 存储位置
K8S_DATA_DIR=/data/disk1

sudo systemctl stop docker
sudo rm -rf /var/lib/containerd /var/openebs /var/lib/kubelet /var/lib/etcd /var/lib/rancher
sudo mkdir -p /var/lib/containerd /var/openebs /var/lib/kubelet /var/lib/etcd /var/lib/rancher /var/local/openebs
sudo mkdir -p $K8S_DATA_DIR/k8s/storage/etcd $K8S_DATA_DIR/k8s/storage/kubelet $K8S_DATA_DIR/k8s/storage/containerd \
  $K8S_DATA_DIR/openebs/storage/var $K8S_DATA_DIR/openebs/storage/local-var $K8S_DATA_DIR/rancher/storage/var $K8S_DATA_DIR/rancher/storage/data
```

准备bind目录 `/etc/fstab`

```bash
# 主 XFS 文件系统，
## XFS文件系统优化选项: largeio,inode64,allocsize=64m,logbsize=256k
## SSD 优化选项 noatime,nodiratime,discard
/dev/nvme0n1p1 /data/disk1 xfs noatime,nodiratime,largeio,inode64,allocsize=64m,logbufs=8,logbsize=512k,noquota 0 2

# Kubernetes 组件 bind mount
/data/disk1/k8s/storage/etcd /var/lib/etcd none bind,noatime,nodiratime,nodev,nosuid,noexec 0 0
/data/disk1/k8s/storage/kubelet /var/lib/kubelet none bind,noatime,nodiratime,nodev,nosuid 0 0
/data/disk1/k8s/storage/containerd /var/lib/containerd none bind,noatime,nodiratime,nodev,nosuid 0 0
/data/disk1/openebs/storage/var /var/openebs none bind,noatime,nodiratime,nodev,nosuid 0 0
/data/disk1/openebs/storage/local-var /var/local/openebs none bind,noatime,nodiratime,nodev,nosuid 0 0
/data/disk1/rancher/storage/var /var/lib/rancher none bind,noatime,nodiratime,nodev,nosuid 0 0

# 配置文件只读绑定
# /data/disk1/k8s/storage/k8s/etc /etc/kubernetes none bind,ro,nodev,nosuid,noexec 0 0
```

```bash

sudo systemctl daemon-reload
sudo mount -a
sudo dpkg-reconfigure containerd

## openebs需要 ( https://openebs.io/docs/quickstart-guide/prerequisites )
## 开启内核选项: nvme_core.multipath=Y
## - debian/RH 似乎默认开启
## - 查看: cat /sys/module/nvme_core/parameters/multipath
echo vm.nr_hugepages = 2048 | sudo tee /etc/sysctl.d/92-container-openebs.conf
sudo sysctl -p /etc/sysctl.d/92-container-openebs.conf
```

NetworkManager 忽略CNI接口

```bash
echo '[keyfile]
unmanaged-devices=interface-name:cali*;interface-name:flannel*;interface-name:eth*,except:interface-name:eth0' | sudo tee '/etc/NetworkManager/conf.d/k8s.conf'

echo '
[Match]
Name=eth[1-9]*

[Link]
Unmanaged=yes
' | sudo tee /etc/systemd/network/99-unmanaged-devices.network
```

## K3S/RKE2

- [k3s.io](https://k3s.io/)
- [rke2.io](https://rke2.io/)

### 初始化

#### 开放端口

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

#### 特权

- NET_RAW : Flannel relies on the Bridge CNI plugin to create a L2 network that switches traffic.

#### Rootless server准备

- 启用 [cgroup v2](https://rootlesscontaine.rs/getting-started/common/cgroup2/)

### 环境变和设置

文档: <https://docs.k3s.io/zh/installation/configuration>

#### K3S环境变量

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

#### RKE2环境变量

| 环境变量                   | 描述                                                                                                                                                                                   |
| -------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `INSTALL_RKE2_VERSION`     | 从 GitHub 下载的 RKE2 版本。如果未指定，将尝试从 stable channel 下载最新版本。如果在基于 RPM 的系统上安装并且 stable channel 中不存在所需的版本，则也应设置 INSTALL_RKE2_CHANNEL。件。 |
| `INSTALL_RKE2_TYPE`        | 要创建的 systemd 服务类型，可以是 "server" 或 "agent"，默认值是 "server"。                                                                                                             |
| `INSTALL_RKE2_CHANNEL_URL` | 用于获取 RKE2 下载 URL 的 Channel URL。默认为 <https://update.rke2.io/v1-release/channels>。                                                                                           |
| `INSTALL_RKE2_CHANNEL`     | 用于获取 RKE2 下载 URL 的 Channel。默认为 stable。可选项：stable、latest、testing。                                                                                                    |
| `INSTALL_RKE2_METHOD`      | 安装方法。默认是基于 RPM 的系统 rpm，所有其他系统都是  tar。                                                                                                                           |

#### 代理环境变量

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

#### 服务器启动

服务器启动选项: <https://docs.k3s.io/zh/cli/server>

重要选项和注意事项:

- `--cluster-cidr=10.42.0.0/16,2001:cafe:42::/56` : CIDR每个节点不能冲突。用于 pod IP 的 IPv4/IPv6 网络 CIDR。
- `--service-cidr=10.43.0.0/16,2001:cafe:43::/112` : 用于服务 IP 的 IPv4/IPv6 网络 CIDR
- `--node-external-ip=<SERVER_EXTERNAL_IP>` : 外网IP
- `--cluster-domain=cluster.local` : 集群域名
- `--tls-san=hostname` : 在 TLS 证书上添加其他主机名或 IPv4/IPv6 地址作为 Subject Alternative Name
- `--config FILE, -c FILE` : 配置路径(/etc/rancher/k3s/config.yaml), `$K3S_CONFIG_FILE`

服务器示例:

```bash
# K3S
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server" sh -s - --flannel-backend none --token 12345
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server --flannel-backend none" K3S_TOKEN=12345 sh -s -
curl -sfL https://get.k3s.io | K3S_TOKEN=12345 sh -s - server --flannel-backend none
# server is assumed below because there is no K3S_URL
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--flannel-backend none --token 12345" sh -s - 
curl -sfL https://get.k3s.io | sh -s - --flannel-backend none --token 12345

# RKE2
## 不要用 INSTALL_RKE2_MIRROR=cn 镜像有缺失
curl -sfL https://get.rke2.io -o install.sh && chmod +x install.sh
# curl -sfL https://rancher-mirror.rancher.cn/rke2/install.sh -o install.sh && chmod +x install.sh

K8S_DATA_DIR=/data/disk1
sudo chmod 777 $K8S_DATA_DIR/rancher/storage/data $K8S_DATA_DIR/rancher/storage/var
sudo mkdir -p /etc/rancher/rke2
sudo cp -f "$PWD/config.yaml" /etc/rancher/rke2/
# sudo mount -a
if [[ -e "$PWD/setup" ]]; then
  sudo cp -rf "$PWD/setup/"* /var/lib/rancher/
  sudo cp -rf "$PWD/setup/rke2/"* $K8S_DATA_DIR/rancher/storage/data/
fi
if [[ -e "$PWD/config.yaml.d/registries.yaml" ]]; then
  sudo cp -f "$PWD/config.yaml.d/registries.yaml" /etc/rancher/rke2/registries.yaml
fi

## Setup server
## 不要用 INSTALL_RKE2_MIRROR=cn 镜像有缺失
sudo env INSTALL_RKE2_CHANNEL=stable RKE2_CONFIG_FILE=/etc/rancher/rke2/config.yaml ./install.sh
sudo sed -i '/RKE2_CONFIG_FILE=/d' /usr/local/lib/systemd/system/rke2-server.env
sudo sed -i '/INSTALL_RKE2_MIRROR=/d' /usr/local/lib/systemd/system/rke2-server.env
sudo sed -i '/INSTALL_RKE2_VERSION=/d' /usr/local/lib/systemd/system/rke2-server.env
echo "RKE2_CONFIG_FILE=/etc/rancher/rke2/config.yaml
INSTALL_RKE2_CHANNEL=stable
" | sudo tee -a /usr/local/lib/systemd/system/rke2-server.env
sudo systemctl start rke2-server && sudo systemctl enable rke2-server

## Setup agent
## 不要用 INSTALL_RKE2_MIRROR=cn 镜像有缺失
sudo env INSTALL_RKE2_CHANNEL=stable INSTALL_RKE2_TYPE="agent" RKE2_CONFIG_FILE=$PWD/config.yaml  ./
sudo sed -i '/RKE2_CONFIG_FILE=/d' /usr/local/lib/systemd/system/rke2-agent.env
sudo sed -i '/INSTALL_RKE2_MIRROR=/d' /usr/local/lib/systemd/system/rke2-agent.env
sudo sed -i '/INSTALL_RKE2_VERSION=/d' /usr/local/lib/systemd/system/rke2-agent.env
echo "RKE2_CONFIG_FILE=$PWD/config.yaml
INSTALL_RKE2_CHANNEL=stable
" | sudo tee -a /usr/local/lib/systemd/system/rke2-agent.env
sudo systemctl start rke2-agent && sudo systemctl enable rke2-agent

# master
systemctl enable rke2-server.service
## 配置 rke2-server 服务
mkdir -p /etc/rancher/rke2/
vim $PWD/config.yaml
### 镜像配置位于 /etc/rancher/rke2/registries.yaml
### 镜像配置位于 /etc/rancher/rke2/
## 启动节点
systemctl start rke2-server.service
## kubeconfig 文件将写入 /etc/rancher/rke2/rke2.yaml
## 可执行文件位于 $K8S_DATA_DIR/rancher/storage/data/bin 或 /var/lib/rancher/rke2/bin
## crictl 配置位于 $K8S_DATA_DIR/rancher/storage/data/agent/etc/crictl.yaml 或 /var/lib/rancher/rke2/agent/etc/crictl.yaml
## 节点令牌在 /var/lib/rancher/rke2/server/node-token

# agent
systemctl enable rke2-agent.service
## 配置 rke2-agent 服务
mkdir -p /etc/rancher/rke2/
vim $PWD/config.yaml
## 启动节点
systemctl start rke2-agent.service
```

##### 启动集群(HA,etcd)

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

##### 启动集群(HA,外部数据库)

启动Server节点:

```bash
curl -sfL https://get.k3s.io | sh -s - server \
  --token=SECRET \
  --datastore-endpoint="mysql://username:password@tcp(hostname:3306)/database-name"
  --tls-san=<FIXED_IP> # Optional, needed if using a fixed registration address
```

可用的数据库选项:

- PostgreSQL: `postgres://username:password@hostname:port/database-name`
- MySQL: `mysql://username:password@tcp(hostname:3306)/database-name`
- etcd: `https://etcd-host-1:2379,https://etcd-host-2:2379,https://etcd-host-3:2379`

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

- `--node-taint CriticalAddonsOnly=true:NoExecute` ： 污点，不会运行用户工作负载

### agent启动

agent启动选项: <https://docs.k3s.io/zh/cli/agent>

agent示例:

```bash
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="agent --server https://k3s.example.com --token mypassword" sh -s -
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="agent" K3S_TOKEN="mypassword" sh -s - --server https://k3s.example.com
curl -sfL https://get.k3s.io | K3S_URL=https://k3s.example.com sh -s - agent --token mypassword
curl -sfL https://get.k3s.io | K3S_URL=https://k3s.example.com K3S_TOKEN=mypassword sh -s - # agent is assumed because of K3S_URL
```

## 集群设置

### 底层容器命令

```bash
K8S_DATA_DIR=/data/disk1
export CRI_CONFIG_FILE=$K8S_DATA_DIR/rancher/storage/data/agent/etc/crictl.yaml
export KUBECONFIG=/etc/rancher/rke2/rke2.yaml
crictl ps -a
crictl logs $(crictl ps -a | grep apiserver | awk '{print $1}') # Container log
crictl events # Find event log path
```

### 常用命令

内置短名称: <https://kubernetes.io/docs/reference/kubectl/#resource-types> 。
所有支持的短名称: `kubectl api-resources | awk 'NF<=4 {printf "%s\n", $1} NF>4 {printf "%-64s%s\n", $1, $2}'`

```bash
# Busybox包含常用工具，可以用来网络测试
kubectl run -it --rm --image=busybox -n kube-system -- bash

# 日志
kubectl logs -n kube-system $ANY_TYPE/$ANY_NAME -f

# 检查节点状态
kubectl get nodes -o wide

# 检查API Server日志
kubectl logs -n kube-system $(kubectl get pods -n kube-system -l component=kube-apiserver -o name | head -1)

# 检查etcd状态
kubectl get pods -n kube-system -l component=etcd

# 查看事件日志
kubectl get events --sort-by='.lastTimestamp' -n kube-system
kubectl get events --sort-by='.lastTimestamp' -n kube-system --field-selector involvedObject.name=$POD_NAME

# 强制重建
kubectl rollout restart daemonset/cilium -n kube-system
kubectl rollout status daemonset/cilium -n kube-system

# 查看Pod创建事件
kubectl describe ds -n kube-system $POD_NAME

# 检查ConfigMap
kubectl get configmap -n kube-system $CONFIGMAP_NAME -o yaml

# 强制移除命名空间
kubectl get namespace $REMOVE_NAMESPACE_NAME -o json | jq '.spec.finalizers = []' | kubectl replace --raw "/api/v1/namespaces/$REMOVE_NAMESPACE_NAME/finalize" -f -
```

### 存储类

```bash
## 默认存储类: https://kubernetes.io/zh-cn/docs/tasks/administer-cluster/change-default-storage-class/
### 查询存储类
kubectl get storageclass
### Unset默认存储类
kubectl patch storageclass standard -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}'
### Set默认存储类
kubectl patch storageclass <your-class-name> -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
```

### 网络

```bash
# cilium (https://docs.cilium.io/en/stable/installation/k8s-install-helm/)
## 检测cilium的状态
kubectl -n kube-system exec ds/cilium -- cilium status --verbose
## 查看k8s集群的node状态
kubectl -n kube-system exec ds/cilium -- cilium node list
## 查看k8s集群的service列表
kubectl -n kube-system exec ds/cilium -- cilium service list
## 查看对应cilium所处node上面的endpoint信息
kubectl -n kube-system exec ds/cilium -- cilium endpoint list
## Test
cilium connectivity test

## 导出当前配置
helm get values cilium -n kube-system > current-values.yaml
## 使用修改后的配置升级
helm upgrade --force cilium cilium/cilium --namespace kube-system --values current-values.yaml

## 检查服务使配置
### 查看当前Cilium配置
kubectl get configmap cilium-config -n kube-system -o yaml | grep -E "(cluster-pool|ipv4|ipv6)"
### 查看Cilium operator配置
kubectl logs -n kube-system deployment/cilium-operator | grep -i "cluster-pool\|cidr"
# 确认要开启2层网络公告
kubectl -n kube-system exec ds/cilium -- cilium-dbg config --all | grep EnableL2Announcements
kubectl -n kube-system exec ds/cilium -- cilium-dbg config --all | grep KubeProxyReplacement
kubectl -n kube-system exec ds/cilium -- cilium-dbg config --all | grep EnableExternalIPs

## 重启服务使配置生效
kubectl rollout restart deployment/cilium-operator -n kube-system
kubectl rollout status deployment/cilium-operator -n kube-system
kubectl rollout restart daemonset/cilium -n kube-system
kubectl rollout status daemonset/cilium -n kube-system
## 重启系统Pod以触发强行重分配IP
# 重启CoreDNS
kubectl rollout restart deployment/coredns -n kube-system
# 如果有其他系统组件，也需要重启
kubectl get pods -n kube-system --no-headers | awk '{print $1}' | xargs kubectl delete pod -n kube-system

## 查看Cilium的IPAM状态
kubectl -n kube-system exec ds/cilium -- cilium-dbg ip list

## 如果需要，可以清理IPAM状态
kubectl -n kube-system exec ds/cilium -- cilium-dbg cleanup

## 完整重新部署
### 卸载Cilium（注意：会中断网络）
helm uninstall cilium -n kube-system
### 清理残留资源
kubectl get crd -o name | grep cilium | xargs kubectl delete
### 重新安装
helm install cilium cilium/cilium -n kube-system -f your-values.yaml
### 等待所有Pod重启
kubectl delete pods --all --all-namespaces

# 删除calico
## 删除资源
kubectl -n kube-system delete ds calico-node
kubectl -n kube-system delete deploy calico-kube-controllers
kubectl -n kube-system delete sa calico-node
kubectl -n kube-system delete sa calico-kube-controllers
kubectl -n kube-system delete cm calico-config
kubectl -n kube-system delete secret calico-config
## 删除CRD
kubectl get crd | grep calico | awk '{print $1}' | xargs kubectl delete crd
## 关闭tunl0
ip link set tunl0 down
## 移除 Calico 配置文件
# rm -rf /etc/cni/net.d/*
```

重新配置集群网络

```bash
# 检查集群 CIDR 配置
kubectl get cm -n kube-system kubeadm-config -o yaml

# 检查 kube-controller-manager
kubectl get pod -n kube-system kube-controller-manager-* -o yaml | grep -A5 -B5 cluster-cidr
```

## 常用Helm仓库

- Hub - <https://artifacthub.io/>
- kubesphere-stable: <https://charts.kubesphere.io/stable>
- rancher: <https://releases.rancher.com/server-charts/>
  - `helm repo add rancher-stable https://releases.rancher.com/server-charts/stable`
  - `helm repo add jetstack https://charts.jetstack.io`
  - `helm repo update`
  - `helm install cert-manager jetstack/cert-manager --namespace cert-manager --create-namespace --set crds.enabled=true`
  - `kubectl create namespace cattle-system`
  - `helm upgrade --install rancher rancher-stable/rancher --namespace cattle-system --set hostname=rancher.w-oa.com --set bootstrapPassword=admin`
  - `kubectl get secret --namespace cattle-system bootstrap-secret -o go-template='{{.data.bootstrapPassword|base64decode}}{{ "\n" }}'`
- bitnami: <https://charts.bitnami.com/bitnami>
- openebs: <https://openebs.github.io/openebs>

```bash
# openebs, 如果 快照卷已存在，则用 --set openebs-crds.csi.volumeSnapshots.enabled=false
helm repo add openebs https://openebs.github.io/charts
# helm install ...
# helm upgrade --install --reuse-values ...
helm upgrade --install --namespace openebs openebs openebs/openebs --create-namespace --set mayastor.etcd.clusterDomain=cluster.devops \
  --set engines.local.lvm.enabled=false --set engines.local.zfs.enabled=false --set openebs-crds.csi.volumeSnapshots.enabled=false \
  --set mayastor.localpv-provisioner.enabled=true --set loki.minio.persistence.size=20Gi

# 当前版本（4.3.0）的 alloy 配置似乎有问题，会报 serviceaccounts "openebs-alloy" not found ，按道理应该由helm charts创建。
# 先不开指标功能，以后有需要再开
--set mayastor.alloy.enabled=true --set mayastor.loki.enabled=true

# 如果kubelet使用非标准目录，要改下面选项 (mount -l | grep /kubelet)
# --set mayastor.csi.node.kubeletDir="/var/lib/kubelet"
# --set lvm-localpv.lvmNode.kubeletDir="/var/lib/kubelet"
# --set zfs-localpv.zfsNode.kubeletDir="/var/lib/kubelet"
kubectl patch storageclass mayastor-etcd-localpv -p '{"allowVolumeExpansion": true}'
kubectl patch storageclass openebs-hostpath -p '{"allowVolumeExpansion": true}'
kubectl patch storageclass openebs-loki-localpv -p '{"allowVolumeExpansion": true}'
kubectl patch storageclass openebs-minio-localpv -p '{"allowVolumeExpansion": true}'
kubectl patch storageclass openebs-hostpath -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
# openebs 的多副本存储(mayastor)配置了反亲和性（topologyKey: kubernetes.io/hostname），必须至少要3哥节点才能正常工作

# 检查存储卷
kubectl get storageclass -o wide
```

- metallb: <https://metallb.github.io/metallb>
- cilium: <https://helm.cilium.io/>
- prometheus-community: <https://prometheus-community.github.io/helm-charts>
- ingress-nginx: <https://kubernetes.github.io/ingress-nginx>
- elastic: <https://helm.elastic.co>
- komodorio: <https://helm-charts.komodor.io>
  - `helm upgrade --install helm-dashboard komodorio/helm-dashboard`

### 额外docker镜像拉取代理域名

- docker.io
- ghcr.io
- registry.k8s.io
- docker.elastic.co
- gcr.io
- quay.io

### 镜像站

- aliyun: <https://kubernetes.oss-cn-hangzhou.aliyuncs.com/charts>

## 新增节点后操作

- helm: `sudo helm plugin install https://github.com/komodorio/helm-dashboard.git`

## 完全删除集群并清理

```bash
K8S_DATA_DIR=/data/disk1
sudo systemctl stop kubelet
sudo kubeadm reset -f

sudo rm -rf /etc/cni/net.d/*
sudo ipvsadm --clear
sudo rm -f /root/.kube/config
sudo rm -rf rm -rf /etc/kubernetes/
sudo rm -rf /etc/systemd/system/kubelet.service.d
sudo rm -rf /etc/systemd/system/kubelet.service
sudo rm -rf $K8S_DATA_DIR/etcd/member

# sudo rm -rf /usr/bin/kube*
# sudo rm -rf rm -rf /etc/cni /opt/cni
# sudo rm -rf /var/lib/etcd

# 清空containerd目录
ps aux | grep /usr/bin/containerd | grep -v grep | awk '{print $2}' | sudo xargs kill
sudo rm -rf $K8S_DATA_DIR/containerd/*
sudo dpkg-reconfigure containerd

# Clear iptables
sudo iptables-save | grep -v KUBE | sudo iptables-restore
# Clear ipvs
sudo ipvsadm -C

# 删除k8s images
sudo ctr -n k8s.io i rm $(sudo ctr -n k8s.io i ls -q)
# 删除k8s containers
sudo ctr -n k8s.io c rm $(sudo ctr -n k8s.io c ls -q)
# 删除k8s snapshot
sudo ctr -n k8s.io snapshots rm $(sudo ctr -n k8s.io snapshots ls | grep -o -E "sha[0-9]+:[0-9a-fA-F]+")
# 删除k8s task
sudo ctr -n k8s.io t rm $(sudo ctr -n k8s.io t ls -q)
# 删除k8s content
sudo ctr -n k8s.io content rm $(sudo ctr -n k8s.io content ls -q)

# 删除openebs数据
sudo rm -rf $K8S_DATA_DIR/openebs/*/*
# 删除etcd数据
sudo rm -rf $K8S_DATA_DIR/etcd/*
```

## 常见问题

### cilium重启后pod启动失败

```bash
Warning   FailedCreate             replicaset/hubble-relay-7b4c9d4474      Error creating: Timeout: request did not complete within requested timeout - context deadline exceeded
Warning   FailedCreate             daemonset/cilium                        Error creating: Timeout: request did not complete within requested timeout - context deadline exceeded
Warning   FailedCreate             daemonset/cilium-envoy                  Error creating: Timeout: request did not complete within requested timeout - context deadline exceeded
Warning   FailedCreate             replicaset/hubble-ui-76d4965bb6         Error creating: Timeout: request did not complete within requested timeout - context deadline exceeded
Warning   FailedCreate             replicaset/cilium-operator-799d64575b   Error creating: Timeout: request did not complete within requested timeout - context deadline exceeded
Warning   FailedCreate             replicaset/hubble-ui-76d4965bb6         Error creating: pods "hubble-ui-76d4965bb6-vvvdq" is forbidden: error looking up service account kube-system/hubble-ui: serviceaccount "hubble-ui" not found
Warning   FailedCreate             replicaset/cilium-operator-799d64575b   Error creating: pods "cilium-operator-799d64575b-dmvr7" is forbidden: error looking up service account kube-system/cilium-operator: serviceaccount "cilium-operator" not found
Warning   FailedCreate             replicaset/hubble-relay-7b4c9d4474      Error creating: pods "hubble-relay-7b4c9d4474-g24lg" is forbidden: error looking up service account kube-system/hubble-relay: serviceaccount "hubble-relay" not found
Warning   FailedCreate             daemonset/cilium-envoy                  Error creating: pods "cilium-envoy-f55k2" is forbidden: error looking up service account kube-system/cilium-envoy: serviceaccount "cilium-envoy" not found
Warning   FailedCreate             daemonset/cilium                        Error creating: pods "cilium-72jj9" is forbidden: error looking up service account kube-system/cilium: serviceaccount "cilium" not found
```


```bash
# 检查现有的ServiceAccount
kubectl get serviceaccount -n kube-system | grep cilium

# 如果ServiceAccount不存在，手动创建
kubectl create serviceaccount cilium -n kube-system
kubectl create serviceaccount cilium-operator -n kube-system
kubectl create serviceaccount hubble-ui -n kube-system
kubectl create serviceaccount hubble-relay -n kube-system
kubectl create serviceaccount cilium-envoy -n kube-system
```

### CNI可执行文件位置错误

debian内cni插件默认指向 `/usr/lib/cni` 但是,k8s安转的cni位于 `/opt/cni/bin`
编辑 `/etc/containerd/config.toml` ，（软连接补全也可以，某些发行版可能配置在 `/etc/cni/net.d/10-calico.conflist` 里）

```toml
version = 2

[plugins]
  [plugins."io.containerd.grpc.v1.cri"]
    [plugins."io.containerd.grpc.v1.cri".cni]
      bin_dir = "/opt/cni/bin"  # 原来是 /usr/lib/cni
      conf_dir = "/etc/cni/net.d"
  [plugins."io.containerd.internal.v1.opt"]
    path = "/var/lib/containerd/opt"
```


### 未知原因nodelocaldns起不来

```bash
sudo kubectl rollout restart daemonset nodelocaldns -n kube-system
```

### 清理openebs资源

```bash
# Check what OpenEBS resources exist
kubectl get all -n openebs
kubectl get sa,clusterrole,clusterrolebinding,cm,secrets,svc,ds,deployments,sts -A | grep openebs

# Delete the specific resources that are causing conflicts
kubectl delete sa openebs-localpv-provisioner -n openebs --ignore-not-found
kubectl get clusterrole -A | grep openebs | awk '{print $1}' | xargs -r kubectl delete clusterrole
kubectl get clusterrolebinding -A | grep openebs | awk '{print $1}' | xargs -r kubectl delete clusterrolebinding
kubectl get deployment -A | grep openebs | awk '{print $1}' | xargs -r kubectl delete deployment


# Remove all OpenEBS resources
kubectl delete namespace openebs
kubectl delete crd -l app=openebs

# Wait for namespace deletion to complete
kubectl get namespace openebs
```
