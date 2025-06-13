#!/bin/bash

function wait_for_seconds() {
    TIMEOUT=$1
    shift
    for ((i = 0; i < $TIMEOUT; i++)); do
        echo -n "."
        if [[ $# -gt 0 ]]; then
            bash -c "$@" >/dev/null 2>&1
            if [[ $? -ne 0 ]]; then
                return 0
            fi
        fi
        sleep 1
    done
}

if [[ "$(id -un)" != "root" ]]; then
    echo "请以root用户身份运行此脚本"
    exit 1
fi

echo "开始完全重置Cilium..."

echo "正在清理Helm"

helm uninstall cilium -n kube-system || echo "Cilium Helm Chart未安装或已清理"

wait_for_seconds 5 "helm list -n kube-system | grep cilium"

echo "正在清理可能遗漏Kubernetes资源..."

# 删除所有Cilium资源
kubectl delete daemonset cilium cilium-envoy -n kube-system --ignore-not-found=true
kubectl delete deployment cilium-operator -n kube-system --ignore-not-found=true
kubectl delete service cilium-envoy cilium-ingress -n kube-system --ignore-not-found=true
kubectl delete configmap cilium-config -n kube-system --ignore-not-found=true
kubectl delete serviceaccount cilium cilium-operator cilium-envoy -n kube-system --ignore-not-found=true

# 清理RBAC资源
kubectl delete clusterrole cilium cilium-operator --ignore-not-found=true
kubectl delete clusterrolebinding cilium cilium-operator --ignore-not-found=true
kubectl delete role cilium-config-agent -n kube-system --ignore-not-found=true
kubectl delete rolebinding cilium-config-agent -n kube-system --ignore-not-found=true

# 等待资源完全删除
echo "等待资源删除"
wait_for_seconds 10

# 强制移除命名空间
if [[ $(kubectl get namespace cilium-secrets -o json >/dev/null 2>&1) -eq 0 ]]; then
    echo "正在强制删除命名空间 cilium-secrets"
    kubectl get namespace cilium-secrets -o json && kubectl get namespace cilium-secrets -o json | jq '.spec.finalizers = []' | kubectl replace --raw "/api/v1/namespaces/cilium-secrets/finalize" -f -
    wait_for_seconds 5 "kubectl get namespace cilium-secrets -o json"
fi

# 验证清理完成
kubectl get all -n kube-system | grep cilium || echo "Cilium资源已完全清理"

rm -rf /var/run/cilium/*

echo "清理完成!"

echo "重新安装 Cilium..."
if [[ $(helm repo list | grep cilium >/dev/null 2>&1) -ne 0 ]]; then
    echo "Cilium Helm 仓库未添加，正在添加..."
    helm repo add cilium https://helm.cilium.io/
    helm repo update
fi

if [[ -e "cilium.version" ]]; then
    CILIUM_VERSION=$(cat cilium.version)
    echo "使用指定版本 Cilium: $CILIUM_VERSION (来自于文件 cilium.version)"
else
    echo "拉取最新版本..."
    CILIUM_VERSION=$(curl -L 'https://api.github.com/repos/cilium/cilium/releases/latest' | grep tag_name | grep -E -o 'v[0-9]+[0-9\.]+' | head -n 1)
    if [[ $? -ne 0 ]]; then
        echo "获取 Cilium 版本失败，使用默认版本 1.15.0"
        exit 0
    fi
    CILIUM_VERSION=${CILIUM_VERSION#v}
    echo "使用版本 Cilium: $CILIUM_VERSION"
    echo "$CILIUM_VERSION" >cilium.version
fi

helm install cilium cilium/cilium --namespace kube-system --version $CILIUM_VERSION -f etc/cilium-helm-values.yaml

cat <<EOF | kubectl apply --server-side -f -
apiVersion: cilium.io/v2
kind: CiliumNodeConfig
metadata:
  namespace: kube-system
  name: cilium-default
spec:
  nodeSelector:
    matchLabels:
      io.cilium.migration/cilium-default: "true"
  defaults:
    write-cni-conf-when-ready: /host/etc/cni/net.d/05-cilium.conflist
    custom-cni-conf: "false"
    cni-chaining-mode: "none"
    cni-exclusive: "true"
EOF
