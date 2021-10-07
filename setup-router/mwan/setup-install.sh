#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"

if [[ ! -e "/etc/NetworkManager/dispatcher.d/up" ]]; then
  echo '#!/bin/bash
for SCRIPT_FILE in /etc/NetworkManager/dispatcher.d/up.d/* ; do
  bash $SCRIPT_FILE "$@"
done

' >/etc/NetworkManager/dispatcher.d/up
  chmod +x /etc/NetworkManager/dispatcher.d/up
fi

mkdir -p "/etc/NetworkManager/dispatcher.d/up.d/"

if [[ -e /etc/NetworkManager/dispatcher.d/up.d/98-setup-multi-wan-up.sh ]]; then
  rm -f /etc/NetworkManager/dispatcher.d/up.d/98-setup-multi-wan-up.sh
fi
ln -sf "$SCRIPT_DIR/setup-multi-wan-up.sh" /etc/NetworkManager/dispatcher.d/up.d/98-setup-multi-wan-up.sh

if [[ ! -e "/etc/NetworkManager/dispatcher.d/down" ]]; then
  echo '#!/bin/bash
for SCRIPT_FILE in /etc/NetworkManager/dispatcher.d/down.d/* ; do
  bash $SCRIPT_FILE "$@"
done

' >/etc/NetworkManager/dispatcher.d/down
  chmod +x /etc/NetworkManager/dispatcher.d/down
fi

mkdir -p "/etc/NetworkManager/dispatcher.d/down.d/"

if [[ -e /etc/NetworkManager/dispatcher.d/down.d/98-setup-multi-wan-down.sh ]]; then
  rm -f /etc/NetworkManager/dispatcher.d/down.d/98-setup-multi-wan-down.sh
fi
ln -sf "$SCRIPT_DIR/setup-multi-wan-down.sh" /etc/NetworkManager/dispatcher.d/down.d/98-setup-multi-wan-down.sh
