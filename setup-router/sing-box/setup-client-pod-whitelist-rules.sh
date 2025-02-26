#!/bin/bash

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
source "$(dirname "$SCRIPT_DIR")/configure-router.sh"

if [[ -z "$VBOX_ETC_DIR" ]]; then
  VBOX_ETC_DIR="$HOME/vbox/etc"
fi

if [[ -z "$VBOX_DATA_DIR" ]]; then
  VBOX_DATA_DIR="$HOME/vbox/data"
fi

if [[ -z "$ROUTER_IP_RULE_GOTO_DEFAULT_PRIORITY" ]]; then
  ROUTER_IP_RULE_GOTO_DEFAULT_PRIORITY=20901
fi

if [[ -z "$VBOX_TUN_TABLE_ID" ]]; then
  VBOX_TUN_TABLE_ID=2035
fi

if [[ "x$1" != "xclear" ]]; then
  VBOX_SETUP_IP_RULE_CLEAR=0
else
  VBOX_SETUP_IP_RULE_CLEAR=1
fi

function vbox_setup_whitelist_ipv4() {
  WHITELIST_TABLE_ID=$(($VBOX_TUN_TABLE_ID + 1))
  TABLE_RULE=($(ip -4 route show table $VBOX_TUN_TABLE_ID | tail -n 1 | awk '{$1="";print $0}'))
  for CIDR in "${VBOX_TUN_PROXY_WHITELIST_IPV4[@]}"; do
    ip -4 route add "$CIDR" "${TABLE_RULE[@]}" table $WHITELIST_TABLE_ID
  done

  # Checking luupup/nop rule
  FIND_PROIRITY=""
  for ((i = 0; i < 5; i++)); do
    FIND_PROIRITY=$(ip -4 rule | grep -E "lookup[[:space:]]+$VBOX_TUN_TABLE_ID" | tail -n 1 | awk 'BEGIN{FS=":"}{print $1}')
    if [[ ! -z "$FIND_PROIRITY" ]]; then
      break
    fi
    sleep 1
  done
  if [[ -z "$FIND_PROIRITY" ]]; then
    FIND_PROIRITY=$(ip -4 rule | grep -E '\bnop\b' | tail -n 1 | awk 'BEGIN{FS=":"}{print $1}')
    if [[ -z "$FIND_PROIRITY" ]]; then
      return 1
    else
      WHITELIST_PROIRITY=$(($FIND_PROIRITY - 1))
    fi
  else
    WHITELIST_PROIRITY=$(($FIND_PROIRITY + 1))
  fi

  ip -4 rule add priority $WHITELIST_PROIRITY lookup $WHITELIST_TABLE_ID
}

function vbox_setup_whitelist_ipv6() {
  WHITELIST_TABLE_ID=$(($VBOX_TUN_TABLE_ID + 1))

  # Checking luupup/nop rule
  FIND_PROIRITY=""
  for ((i = 0; i < 5; i++)); do
    FIND_PROIRITY=$(ip -6 rule | grep -E "lookup[[:space:]]+$VBOX_TUN_TABLE_ID" | tail -n 1 | awk 'BEGIN{FS=":"}{print $1}')
    if [[ ! -z "$FIND_PROIRITY" ]]; then
      break
    fi
    sleep 1
  done
  if [[ -z "$FIND_PROIRITY" ]]; then
    FIND_PROIRITY=$(ip -6 rule | grep -E '\bnop\b' | tail -n 1 | awk 'BEGIN{FS=":"}{print $1}')
    if [[ -z "$FIND_PROIRITY" ]]; then
      return 1
    else
      WHITELIST_PROIRITY=$(($FIND_PROIRITY - 1))
    fi
  else
    WHITELIST_PROIRITY=$(($FIND_PROIRITY + 1))
  fi

  ip -6 rule add priority $WHITELIST_PROIRITY lookup $WHITELIST_TABLE_ID || return 1

  TABLE_RULE=($(ip -6 route show table $VBOX_TUN_TABLE_ID | tail -n 1 | awk '{$1="";print $0}'))
  for CIDR in "${VBOX_TUN_PROXY_WHITELIST_IPV6[@]}"; do
    ip -6 route add "$CIDR" "${TABLE_RULE[@]}" table $WHITELIST_TABLE_ID
  done
}

function vbox_cleanup_whitelist_ipv4() {
  WHITELIST_TABLE_ID=$(($VBOX_TUN_TABLE_ID + 1))
  ROUTER_IP_RULE_LOOPUP_VBOX_SKIP_PRIORITY=$(ip -4 rule show lookup $WHITELIST_TABLE_ID | awk 'END {print NF}')
  while [[ 0 -ne $ROUTER_IP_RULE_LOOPUP_VBOX_SKIP_PRIORITY ]]; do
    ip -4 rule delete lookup $WHITELIST_TABLE_ID
    ROUTER_IP_RULE_LOOPUP_VBOX_SKIP_PRIORITY=$(ip -4 rule show lookup $WHITELIST_TABLE_ID | awk 'END {print NF}')
  done

  ip -4 route flush table $WHITELIST_TABLE_ID || true
}

function vbox_cleanup_whitelist_ipv6() {
  WHITELIST_TABLE_ID=$(($VBOX_TUN_TABLE_ID + 1))
  ROUTER_IP_RULE_LOOPUP_VBOX_SKIP_PRIORITY=$(ip -6 rule show lookup $WHITELIST_TABLE_ID | awk 'END {print NF}')
  while [[ 0 -ne $ROUTER_IP_RULE_LOOPUP_VBOX_SKIP_PRIORITY ]]; do
    ip -6 rule delete lookup $WHITELIST_TABLE_ID
    ROUTER_IP_RULE_LOOPUP_VBOX_SKIP_PRIORITY=$(ip -6 rule show lookup $WHITELIST_TABLE_ID | awk 'END {print NF}')
  done

  ip -6 route flush table $WHITELIST_TABLE_ID || true
}

vbox_cleanup_whitelist_ipv4
vbox_cleanup_whitelist_ipv6

if [[ $VBOX_SETUP_IP_RULE_CLEAR -eq 0 ]] && [[ ${#VBOX_TUN_PROXY_WHITELIST_IPV4[@]} -gt 0 ]]; then
  vbox_setup_whitelist_ipv4
fi

if [[ $VBOX_SETUP_IP_RULE_CLEAR -eq 0 ]] && [[ ${#VBOX_TUN_PROXY_WHITELIST_IPV6[@]} -gt 0 ]]; then
  vbox_setup_whitelist_ipv6
fi
