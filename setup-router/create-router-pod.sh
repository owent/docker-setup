#!/bin/bash

# $ROUTER_HOME/create-router-pod.sh

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
source "$SCRIPT_DIR/configure-router.sh"

systemctl --all | grep -F router.service >/dev/null 2>&1

if [[ $? -eq 0 ]]; then
  systemctl stop router
  systemctl disable router
fi

podman container exists router

if [[ $? -eq 0 ]]; then
  podman stop router
  podman rm -f router
fi

podman run -d --name router --systemd true --security-opt label=disable \
  --mount type=bind,source=$ROUTER_HOME,target=$ROUTER_HOME \
  --mount type=bind,source=/dev/ppp,target=/dev/ppp \
  --cap-add=NET_ADMIN --network=host local-router /lib/systemd/systemd

podman generate systemd router | tee /lib/systemd/system/router.service

systemctl enable router
systemctl start router

echo "[Unit]
Description=Setup router
After=network.target network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/bin/bash $ROUTER_HOME/setup-services.sh
RemainAfterExit=yes

[Install]
WantedBy=default.target
" >"$ROUTER_HOME/router-on-startup.service"

podman cp $ROUTER_HOME/router-on-startup.service router:/lib/systemd/system/router-on-startup.service
podman exec router systemctl enable router-on-startup
podman exec router systemctl start router-on-startup
