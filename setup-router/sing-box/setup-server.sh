#!/bin/bash

cd "$(dirname "${BASH_SOURCE[0]}")"

if [[ "$(whoami)" == "tools" ]]; then
  env VBOX_ETC_DIR=/data/vbox-server/etc VBOX_LOG_DIR=/data/vbox-server/log VBOX_SSL_DIR=/home/website/ssl $PWD/create-server-pod.sh
else
  su - tools -c "env VBOX_ETC_DIR=/data/vbox-server/etc VBOX_LOG_DIR=/data/vbox-server/log VBOX_SSL_DIR=/home/website/ssl $PWD/create-server-pod.sh"
fi
