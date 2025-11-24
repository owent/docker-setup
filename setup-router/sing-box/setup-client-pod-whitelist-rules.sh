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
  ROUTER_IP_RULE_GOTO_DEFAULT_PRIORITY=9091
fi

if [[ -z "$VBOX_SKIP_IP_RULE_PRIORITY" ]]; then
  VBOX_SKIP_IP_RULE_PRIORITY=8123
fi

if [[ -z "$VBOX_TUN_TABLE_ID" ]]; then
  VBOX_TUN_TABLE_ID=2022
fi

if [[ -z "$VBOX_TUN_PROXY_WHITELIST_TABLE_ID" ]]; then
  VBOX_TUN_PROXY_WHITELIST_TABLE_ID=$(($VBOX_TUN_TABLE_ID - 200))
fi

if [[ -z "$VBOX_TUN_PROXY_BLACKLIST_IFNAME" ]]; then
  VBOX_TUN_PROXY_BLACKLIST_IFNAME=()
fi

if [[ "x$1" != "xclear" ]]; then
  VBOX_SETUP_IP_RULE_CLEAR=0
else
  VBOX_SETUP_IP_RULE_CLEAR=1
fi

function vbox_get_last_tun_lookup_priority() {
  if [[ ! -z "$VBOX_TUN_ENABLE_AUTO_ROUTE" ]] && [[ $VBOX_TUN_ENABLE_AUTO_ROUTE -eq 0 ]]; then
    return 0
  fi

  IP_FAMILY="$1"
  FIND_PROIRITY=""
  for ((i = 0; i < 10; i++)); do
    FIND_PROIRITY=$(ip $IP_FAMILY rule list | grep -E "\\blookup[[:space:]]+$VBOX_TUN_TABLE_ID\$" | tail -n 1 | awk 'BEGIN{FS=":"}{print $1}')
    if [[ ! -z "$FIND_PROIRITY" ]]; then
      break
    fi
    sleep 1
  done
  if [[ -z "$FIND_PROIRITY" ]]; then
    return 1
  fi

  echo "$FIND_PROIRITY"
}

function vbox_get_first_nop_lookup_priority_after_tun() {
  if [[ ! -z "$VBOX_TUN_ENABLE_AUTO_ROUTE" ]] && [[ $VBOX_TUN_ENABLE_AUTO_ROUTE -eq 0 ]]; then
    return 0
  fi

  IP_FAMILY="$1"
  TUN_PRIORITY=$2
  FIND_PROIRITY=""
  if [[ -z "$TUN_PRIORITY" ]]; then
    for ((i = 0; i < 10; i++)); do
      FIND_PROIRITY=$(ip $IP_FAMILY rule show | grep -E '\bnop$' | tail -n 1 | awk 'BEGIN{FS=":"}{print $1}')
      if [[ ! -z "$FIND_PROIRITY" ]]; then
        break
      fi
      sleep 1
    done
  else
    for ((i = 0; i < 10; i++)); do
      FIND_PROIRITY=$(ip $IP_FAMILY rule show | grep -E '\bnop$' | awk "BEGIN{FS=\":\"} \$1>$TUN_PRIORITY {print \$1}" | head -n 1)
      if [[ ! -z "$FIND_PROIRITY" ]]; then
        break
      fi
      sleep 1
    done
  fi
  if [[ -z "$FIND_PROIRITY" ]]; then
    return 1
  fi

  echo "$FIND_PROIRITY"
}

function vbox_setup_whitelist_ipv4() {
  # Checking lookup/nop rule
  LAST_TUN_LOOKUP_PRIORITY=$(vbox_get_last_tun_lookup_priority "-4")
  NOP_LOOKUP_PRIORITY=$(vbox_get_first_nop_lookup_priority_after_tun "-4" "$LAST_TUN_LOOKUP_PRIORITY")

  if [[ -z "$NOP_LOOKUP_PRIORITY" ]]; then
    ip -4 rule add nop priority $ROUTER_IP_RULE_GOTO_DEFAULT_PRIORITY
    NOP_LOOKUP_PRIORITY=$ROUTER_IP_RULE_GOTO_DEFAULT_PRIORITY
  fi

  if [[ -z "$LAST_TUN_LOOKUP_PRIORITY" ]]; then
    WHITELIST_PROIRITY=$(($VBOX_SKIP_IP_RULE_PRIORITY + 1))
  else
    WHITELIST_PROIRITY=$(($LAST_TUN_LOOKUP_PRIORITY + 1))
  fi

  TABLE_RULE=($(ip -4 route show table $VBOX_TUN_TABLE_ID | tail -n 1 | awk '{$1="";print $0}' | grep -E -o '.*dev[[:space:]]+[^[:space:]]+'))
  for CIDR in "${VBOX_TUN_PROXY_WHITELIST_IPV4[@]}"; do
    ip -4 route add "$CIDR" "${TABLE_RULE[@]}" table $VBOX_TUN_PROXY_WHITELIST_TABLE_ID
  done
  ip -4 rule add priority $WHITELIST_PROIRITY lookup $VBOX_TUN_PROXY_WHITELIST_TABLE_ID || return 1

  for SERVICE_PORT in $(echo $ROUTER_INTERNAL_SERVICE_PUBLIC_PORT_TCP | tr ',' ' '); do
    ip -4 rule add priority $VBOX_SKIP_IP_RULE_PRIORITY ipproto tcp sport $SERVICE_PORT goto $NOP_LOOKUP_PRIORITY
  done
  for SERVICE_PORT in $(echo $ROUTER_INTERNAL_SERVICE_PUBLIC_PORT_UDP | tr ',' ' '); do
    ip -4 rule add priority $VBOX_SKIP_IP_RULE_PRIORITY ipproto udp sport $SERVICE_PORT goto $NOP_LOOKUP_PRIORITY
  done
  for BLACKLIST_IFNAME in $(echo $VBOX_TUN_PROXY_BLACKLIST_IFNAME | tr ',' ' '); do
    ip -4 rule add priority $VBOX_SKIP_IP_RULE_PRIORITY iif $BLACKLIST_IFNAME goto $NOP_LOOKUP_PRIORITY
  done
}

function vbox_setup_whitelist_ipv6() {
  # Checking lookup/nop rule
  LAST_TUN_LOOKUP_PRIORITY=$(vbox_get_last_tun_lookup_priority "-6")
  NOP_LOOKUP_PRIORITY=$(vbox_get_first_nop_lookup_priority_after_tun "-6" "$LAST_TUN_LOOKUP_PRIORITY")

  if [[ -z "$NOP_LOOKUP_PRIORITY" ]]; then
    ip -6 rule add nop priority $ROUTER_IP_RULE_GOTO_DEFAULT_PRIORITY
    NOP_LOOKUP_PRIORITY=$ROUTER_IP_RULE_GOTO_DEFAULT_PRIORITY
  fi

  if [[ -z "$LAST_TUN_LOOKUP_PRIORITY" ]]; then
    WHITELIST_PROIRITY=$(($VBOX_SKIP_IP_RULE_PRIORITY + 1))
  else
    WHITELIST_PROIRITY=$(($LAST_TUN_LOOKUP_PRIORITY + 1))
  fi

  TABLE_RULE=($(ip -6 route show table $VBOX_TUN_TABLE_ID | tail -n 1 | awk '{$1="";print $0}' | grep -E -o '.*dev[[:space:]]+[^[:space:]]+'))
  for CIDR in "${VBOX_TUN_PROXY_WHITELIST_IPV6[@]}"; do
    ip -6 route add "$CIDR" "${TABLE_RULE[@]}" table $VBOX_TUN_PROXY_WHITELIST_TABLE_ID
  done
  ip -6 rule add priority $WHITELIST_PROIRITY lookup $VBOX_TUN_PROXY_WHITELIST_TABLE_ID || return 1

  for SERVICE_PORT in $(echo $ROUTER_INTERNAL_SERVICE_PUBLIC_PORT_TCP | tr ',' ' '); do
    ip -6 rule add priority $VBOX_SKIP_IP_RULE_PRIORITY ipproto tcp sport $SERVICE_PORT goto $NOP_LOOKUP_PRIORITY
  done
  for SERVICE_PORT in $(echo $ROUTER_INTERNAL_SERVICE_PUBLIC_PORT_UDP | tr ',' ' '); do
    ip -6 rule add priority $VBOX_SKIP_IP_RULE_PRIORITY ipproto udp sport $SERVICE_PORT goto $NOP_LOOKUP_PRIORITY
  done
  for BLACKLIST_IFNAME in $(echo $VBOX_TUN_PROXY_BLACKLIST_IFNAME | tr ',' ' '); do
    ip -6 rule add priority $VBOX_SKIP_IP_RULE_PRIORITY iif $BLACKLIST_IFNAME goto $NOP_LOOKUP_PRIORITY
  done
}

function vbox_clear_ip_priority() {
  for IP_FAMILY in "$@"; do
    for CLEAR_PRIORITY in "$VBOX_SKIP_IP_RULE_PRIORITY" \
                          "$ROUTER_IP_RULE_GOTO_DEFAULT_PRIORITY"; do
      ROUTER_IP_RULE_LOOPUP_PRIORITY=$(ip $IP_FAMILY rule show priority $CLEAR_PRIORITY | awk 'END {print NF}')
      while [[ 0 -ne $ROUTER_IP_RULE_LOOPUP_PRIORITY ]]; do
        ip $IP_FAMILY rule delete priority $CLEAR_PRIORITY
        ROUTER_IP_RULE_LOOPUP_PRIORITY=$(ip $IP_FAMILY rule show priority $CLEAR_PRIORITY | awk 'END {print NF}')
      done
    done

    # clear ip route table
    ROUTER_IP_RULE_LOOPUP_VBOX_SKIP_PRIORITY=$(ip $IP_FAMILY rule show lookup $VBOX_TUN_PROXY_WHITELIST_TABLE_ID | awk 'END {print NF}')
    while [[ 0 -ne $ROUTER_IP_RULE_LOOPUP_VBOX_SKIP_PRIORITY ]]; do
      ip $IP_FAMILY rule delete lookup $VBOX_TUN_PROXY_WHITELIST_TABLE_ID
      ROUTER_IP_RULE_LOOPUP_VBOX_SKIP_PRIORITY=$(ip $IP_FAMILY rule show lookup $VBOX_TUN_PROXY_WHITELIST_TABLE_ID | awk 'END {print NF}')
    done

    ip $IP_FAMILY route flush table $VBOX_TUN_PROXY_WHITELIST_TABLE_ID || true
  done
}

vbox_clear_ip_priority "-4" "-6"

if [[ $VBOX_SETUP_IP_RULE_CLEAR -eq 0 ]] && [[ ${#VBOX_TUN_PROXY_WHITELIST_IPV4[@]} -gt 0 ]]; then
  vbox_setup_whitelist_ipv4
  if [[ $? -ne 0 ]]; then
    echo "Failed to setup IPv4 whitelist rules."
    exit 1
  fi
fi

if [[ $VBOX_SETUP_IP_RULE_CLEAR -eq 0 ]] && [[ ${#VBOX_TUN_PROXY_WHITELIST_IPV6[@]} -gt 0 ]]; then
  vbox_setup_whitelist_ipv6
fi

# clear DNS server cache
# su tools -l -c 'env XDG_RUNTIME_DIR="/run/user/$UID" DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR}/bus" systemctl --user restart container-adguard-home'
