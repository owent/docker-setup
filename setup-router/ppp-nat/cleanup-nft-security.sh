#!/bin/bash

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
source "$(dirname "$SCRIPT_DIR")/configure-router.sh"

nft list table inet security_firewall >/dev/null 2>&1
if [[ $? -eq 0 ]]; then
  nft delete table inet security_firewall
fi
