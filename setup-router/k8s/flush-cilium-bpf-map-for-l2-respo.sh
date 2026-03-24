#!/bin/bash

#!/bin/bash
PID=$(sudo pidof cilium-agent)
BPF=/usr/local/bin/bpftool
# 获取 IPv4 map ID
MAP4=$(sudo nsenter -t $PID -m -n $BPF map show | grep 'cilium_l2_respo' | head -1 | cut -d: -f1 | tr -d ' ')
# Flush IPv4 map
sudo nsenter -t $PID -m -n $BPF map dump id $MAP4 | grep '^key:' | sed 's/key: //; s/  value:.*//' | while read k; do
  sudo nsenter -t $PID -m -n $BPF map delete id $MAP4 key hex $k
done
# 重启 cilium-agent 容器
CID=$(sudo /var/lib/rancher/rke2/bin/crictl --runtime-endpoint unix:///run/k3s/containerd/containerd.sock ps --name cilium-agent -q | head -1)
sudo /var/lib/rancher/rke2/bin/crictl --runtime-endpoint unix:///run/k3s/containerd/containerd.sock stop $CID
