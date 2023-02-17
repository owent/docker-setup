#!/bin/bash

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
source "$(dirname "$SCRIPT_DIR")/configure-router.sh"

nft list table inet security_firewall >/dev/null 2>&1
if [[ $? -eq 0 ]]; then
  FLUSH_CHAINS=(PREROUTING INPUT OUTPUT FORWARD)
  for TEST_CHAIN_NAME in ${FLUSH_CHAINS[@]}; do
    nft list chain inet security_firewall $TEST_CHAIN_NAME >/dev/null 2>&1
    if [[ $? -eq 0 ]]; then
      nft delete chain inet security_firewall $TEST_CHAIN_NAME
    fi
  done
fi
