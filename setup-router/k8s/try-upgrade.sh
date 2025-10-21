#!/bin/bash
#

if  [[  ! -z "K8S_NO_UPDATE_SCRIPT" ]] && [[ "K8S_NO_UPDATE_SCRIPT" != "0" ]] &&
  [[ "K8S_NO_UPDATE_SCRIPT" != "no" ]] && [[ "K8S_NO_UPDATE_SCRIPT" != "false" ]] &&
  [[ -e "install.sh" ]]; then
  curl -sfL https://get.rke2.io -o install.sh

  if [[ $? -ne 0 ]]; then
    echo "Download rke2 install.sh failed"
    exit 1
  fi

  chmod +x install.sh
fi

sudo systemctl disable rke2-server
sudo systemctl stop rke2-server
sudo rke2-killall.sh

sleep 3
ps aux | grep rancher | grep -v grep | awk '{print $2}' | sudo xargs -r kill
sleep 2

if  [[  ! -z "K8S_FORCE_CLEANUP" ]] && [[ "K8S_FORCE_CLEANUP" != "0" ]] &&
  [[ "K8S_FORCE_CLEANUP" != "no" ]] && [[ "K8S_FORCE_CLEANUP" != "false" ]]; then
  rke2-uninstall.sh

  # Clear iptables
  iptables-save | grep -v KUBE | sudo iptables-restore
  # Clear ipvs
  ipvsadm -C
fi

if [[ -z "$K8S_DATA_DIR" ]]; then
  K8S_DATA_DIR=data/k8s
fi
sudo chmod 777 $K8S_DATA_DIR/rancher/storage/data $K8S_DATA_DIR/rancher/storage/var
# sudo mount -a
if [[ -e "$PWD/setup" ]]; then
  sudo cp -rf "$PWD/setup/"* /var/lib/rancher/
  # sudo cp -rf "$PWD/setup/rke2/"* $K8S_DATA_DIR/rancher/storage/data/
fi
sudo mkdir -p /etc/rancher/rke2
sudo cp -f "$PWD/config.yaml" /etc/rancher/rke2/

if [[ -e "$PWD/config.yaml.d/registries.yaml" ]]; then
  sudo cp -f "$PWD/config.yaml.d/registries.yaml" /etc/rancher/rke2/registries.yaml
fi

## Setup server
sudo env INSTALL_RKE2_CHANNEL=stable RKE2_CONFIG_FILE=/etc/rancher/rke2/config.yaml ./install.sh
sudo sed -i '/RKE2_CONFIG_FILE=/d' /usr/local/lib/systemd/system/rke2-server.env
sudo sed -i '/INSTALL_RKE2_VERSION=/d' /usr/local/lib/systemd/system/rke2-server.env
echo "RKE2_CONFIG_FILE=/etc/rancher/rke2/config.yaml
INSTALL_RKE2_CHANNEL=stable" | sudo tee -a /usr/local/lib/systemd/system/rke2-server.env
sudo systemctl start rke2-server
