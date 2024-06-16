#!/bin/bash

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
source "$SCRIPT_DIR/configure-router.sh"

NETWORKMANAGER_DISPATCHER_DIR="/etc/NetworkManager/dispatcher.d"

function networkmanager_create_dispatcher_script_dir() {
  if [[ ! -e "$NETWORKMANAGER_DISPATCHER_DIR/$1" ]]; then
    echo '#!/bin/bash
echo "[$(date "+%F %T")]: $0 $@
  CONNECTION_ID=$CONNECTION_ID
  CONNECTION_UUID=$CONNECTION_UUID
  NM_DISPATCHER_ACTION=$NM_DISPATCHER_ACTION
  CONNECTIVITY_STATE=$CONNECTIVITY_STATE
  DEVICE_IFACE=$DEVICE_IFACE
  DEVICE_IP_IFACE=$DEVICE_IP_IFACE
  IP4_GATEWAY=$IP4_GATEWAY
  IP6_GATEWAY=$IP6_GATEWAY
============
$(ip -4 -o addr)
-----------
$(ip -6 -o addr)" | systemd-cat -t router-mwan -p info ;
' >"$NETWORKMANAGER_DISPATCHER_DIR/$1"
    chmod +x "$NETWORKMANAGER_DISPATCHER_DIR/$1"
  fi

  grep -F "$NETWORKMANAGER_DISPATCHER_DIR/$1.d/" "$NETWORKMANAGER_DISPATCHER_DIR/$1" || echo "
for SCRIPT_FILE in \$(find $NETWORKMANAGER_DISPATCHER_DIR/$1.d -name '*.sh') ; do
  if [ -e \"\$SCRIPT_FILE\" ]; then
    bash \$SCRIPT_FILE "$@"
  fi
done
" >>"$NETWORKMANAGER_DISPATCHER_DIR/$1"
  mkdir -p "$NETWORKMANAGER_DISPATCHER_DIR/$1.d/"
}

networkmanager_create_dispatcher_script_dir up
networkmanager_create_dispatcher_script_dir down
networkmanager_create_dispatcher_script_dir connectivity-change

if [[ -e "$SCRIPT_DIR/reset-local-address-sets.sh" ]]; then
  echo "Maybe need run these codes below for router:
echo '#!/bin/bash
/bin/bash $SCRIPT_DIR/reset-local-address-sets.sh
' | sudo tee /etc/NetworkManager/dispatcher.d/connectivity-change.d/99-reset-local-address-sets.sh
sudo chmod +x /etc/NetworkManager/dispatcher.d/connectivity-change.d/99-reset-local-address-sets.sh"
fi
