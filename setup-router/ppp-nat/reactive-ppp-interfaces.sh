#!/bin/bash

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
source "$(dirname "$SCRIPT_DIR")/configure-router.sh"

ALL_PPP_INERFACES=($(nmcli --fields NAME,TYPE connection show | grep 'pppoe' | awk '{print $1}'))
ACTIVED_PPP_INERFACES=($(nmcli --fields NAME,TYPE connection show --active | grep 'pppoe' | awk '{print $1}'))
BAN_PPP_INERFACES=() # ppp1

function check_actived() {
  for CHECK_INERFACE in ${ACTIVED_PPP_INERFACES[@]}; do
    if [[ "$1" == "$CHECK_INERFACE" ]]; then
      return 0
    fi
  done
  return 1
}

function check_banned() {
  for CHECK_INERFACE in ${BAN_PPP_INERFACES[@]}; do
    if [[ "$1" == "$CHECK_INERFACE" ]]; then
      return 0
    fi
  done
  return 1
}

function nmcli_up_connection() {
  echo "nmcli connection up $1" | systemd-cat -t router-ppp -p info
  nmcli connection up "$1"
}

echo "All pppoe interfaces: ${ALL_PPP_INERFACES[@]}"
echo "Actived pppoe interfaces: ${ACTIVED_PPP_INERFACES[@]}"

for PPP_INERFACE in ${ALL_PPP_INERFACES[@]}; do
  check_actived "$PPP_INERFACE" || check_banned "$PPP_INERFACE" || nmcli_up_connection "$PPP_INERFACE"
done
