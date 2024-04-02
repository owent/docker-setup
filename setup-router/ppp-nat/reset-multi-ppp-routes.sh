#!/bin/bash

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
source "$(dirname "$SCRIPT_DIR")/configure-router.sh"

PPP_DEVICE=($(nmcli --fields=DEVICE,TYPE d status | awk '$2 == "ppp"{print $1}'))
if [[ ${#PPP_DEVICE[@]} -lt 2 ]]; then
  exit 0
fi
MULTI_PPP_START_PRIORITY=32600
MULTI_PPP_START_TABLE_ID=32600

CURRENT_INDEX=0
for CURRENT_PPP_DEVICE in ${PPP_DEVICE[@]}; do
  CURRENT_INDEX=$(($CURRENT_INDEX + 1))
  CURRENT_PRIORITY=$(($MULTI_PPP_START_PRIORITY + $CURRENT_INDEX))
  CURRENT_TABLE_ID=$(($MULTI_PPP_START_TABLE_ID + $CURRENT_INDEX))

  # Cleanup default route rule - ipv4
  CURRENT_LOOPUP_TABLE=$(ip -4 rule show lookup $CURRENT_TABLE_ID | awk 'END {print NF}')
  while [[ 0 -ne $CURRENT_LOOPUP_TABLE ]]; do
    ip -4 rule delete lookup $CURRENT_TABLE_ID
    CURRENT_LOOPUP_TABLE=$(ip -4 rule show lookup $CURRENT_TABLE_ID | awk 'END {print NF}')
  done
  # Cleanup default route table
  ip -4 route flush table $CURRENT_TABLE_ID >/dev/null 2>&1 || true

  # Cleanup default route rule - ipv6
  CURRENT_LOOPUP_TABLE=$(ip -6 rule show lookup $CURRENT_TABLE_ID | awk 'END {print NF}')
  while [[ 0 -ne $CURRENT_LOOPUP_TABLE ]]; do
    ip -6 rule delete lookup $CURRENT_TABLE_ID
    CURRENT_LOOPUP_TABLE=$(ip -6 rule show lookup $CURRENT_TABLE_ID | awk 'END {print NF}')
  done
  # Cleanup default route table
  ip -6 route flush table $CURRENT_TABLE_ID >/dev/null 2>&1 || true

  CURRENT_DEFAULT_IPV4_ROUTE_VIA_IP=$(ip -4 route show default dev $CURRENT_PPP_DEVICE | awk 'match($0, /via\s+([0-9a-fA-F\.]+(\/[0-9]+)?)/, ip) { print ip[1] }')
  CURRENT_DEFAULT_IPV6_ROUTE_VIA_IP=$(ip -6 route show default dev $CURRENT_PPP_DEVICE | awk 'match($0, /via\s+([0-9a-fA-F:]+(\/[0-9]+)?)/, ip) { print ip[1] }')
  CURRENT_NEW_IPV4_ROUTE_VIA_IP=$(ip -o -4 addr show dev $CURRENT_PPP_DEVICE | awk 'match($0, /peer\s+([0-9a-fA-F\.]+(\/[0-9]+)?)/, ip) { print ip[1] }' | head -n 1)
  CURRENT_NEW_IPV6_ROUTE_VIA_IP=$(ip -o -6 addr show dev $CURRENT_PPP_DEVICE | awk 'match($0, /peer\s+([0-9a-fA-F:]+(\/[0-9]+)?)/, ip) { print ip[1] }' | head -n 1)
  CURRENT_NEW_IPV4_ROUTE_VIA_IP="${CURRENT_NEW_IPV4_ROUTE_VIA_IP%/*}"
  CURRENT_NEW_IPV6_ROUTE_VIA_IP="${CURRENT_NEW_IPV6_ROUTE_VIA_IP%/*}"

  # Setup ipv4 rule
  CURRENT_DEFAULT_ROUTE_LIST=()
  for IPV4_ADDR in $(ip -o -4 addr show dev $CURRENT_PPP_DEVICE | awk 'match($0, /inet\s+([0-9a-fA-F\.]+(\/[0-9]+)?)/, ip) { print ip[1] }'); do
    if [[ "x$CURRENT_DEFAULT_IPV4_ROUTE_VIA_IP" != "x" ]] || [[ "x$CURRENT_NEW_IPV4_ROUTE_VIA_IP" == "x" ]]; then
      break
    fi
    # Setup ip rule
    echo "Run: ip -4 rule add priority $CURRENT_PRIORITY from $IPV4_ADDR lookup $CURRENT_TABLE_ID"
    ip -4 rule add priority $CURRENT_PRIORITY from $IPV4_ADDR lookup $CURRENT_TABLE_ID

    CURRENT_DEFAULT_ROUTE_LIST=(${CURRENT_DEFAULT_ROUTE_LIST[@]} "$IPV4_ADDR")
  done
  for CURRENT_DEFAULT_ROUTE_ADDRESS in $(echo ${CURRENT_DEFAULT_ROUTE_LIST[@]} | tr ' ' '\n' | sort -u); do
    echo "Run: ip -4 route add default via "$CURRENT_NEW_IPV4_ROUTE_VIA_IP" from "$CURRENT_DEFAULT_ROUTE_ADDRESS" dev $CURRENT_PPP_DEVICE table $CURRENT_TABLE_ID"
    ip -4 route add default via "$CURRENT_NEW_IPV4_ROUTE_VIA_IP" from "$CURRENT_DEFAULT_ROUTE_ADDRESS" dev $CURRENT_PPP_DEVICE table $CURRENT_TABLE_ID
  done

  # Setup ipv6 rule
  CURRENT_DEFAULT_ROUTE_LIST=()
  for IPV6_ADDR in $(ip -o -6 addr show dev $CURRENT_PPP_DEVICE | awk 'match($0, /inet6\s+([0-9a-fA-F:]+(\/[0-9]+)?)/, ip) { print ip[1] }'); do
    if [[ "x$CURRENT_DEFAULT_IPV6_ROUTE_VIA_IP" != "x" ]] || [[ "x$CURRENT_NEW_IPV6_ROUTE_VIA_IP" == "x" ]]; then
      break
    fi
    # Setup ip rule
    echo "Run: ip -6 rule add priority $CURRENT_PRIORITY from $IPV6_ADDR lookup $CURRENT_TABLE_ID"
    ip -6 rule add priority $CURRENT_PRIORITY from $IPV6_ADDR lookup $CURRENT_TABLE_ID

    IPV6_ADDR_SUFFIX=$(echo "$IPV6_ADDR" | awk '{if(match($0, /\/([0-9]+)/, suffix)) { print suffix[1]; } else { print 128; } }')
    if [[ $IPV6_ADDR_SUFFIX -ge 128 ]]; then
      CURRENT_DEFAULT_ROUTE_LIST=(${CURRENT_DEFAULT_ROUTE_LIST[@]} "$IPV6_ADDR")
    else
      IPV6_ADDR_PREFIX=""
      let IPV6_ADDR_BR_SUFFIX=$IPV6_ADDR_SUFFIX
      for IPV6_ADDR_PREFIX_SEGMENT in ${IPV6_ADDR//:/ }; do
        if [[ $IPV6_ADDR_SUFFIX -le 0 ]]; then
          break
        fi
        if [[ -z "$IPV6_ADDR_PREFIX" ]]; then
          IPV6_ADDR_PREFIX="$IPV6_ADDR_PREFIX_SEGMENT"
        else
          IPV6_ADDR_PREFIX="$IPV6_ADDR_PREFIX:$IPV6_ADDR_PREFIX_SEGMENT"
        fi
        let IPV6_ADDR_SUFFIX=$IPV6_ADDR_SUFFIX-16
      done
      CURRENT_DEFAULT_ROUTE_LIST=(${CURRENT_DEFAULT_ROUTE_LIST[@]} "$IPV6_ADDR_PREFIX::/$IPV6_ADDR_BR_SUFFIX")
    fi
  done
  for CURRENT_DEFAULT_ROUTE_ADDRESS in $(echo ${CURRENT_DEFAULT_ROUTE_LIST[@]} | tr ' ' '\n' | sort -u); do
    echo "Run: ip -6 route add default via "$CURRENT_NEW_IPV6_ROUTE_VIA_IP" from "$CURRENT_DEFAULT_ROUTE_ADDRESS" dev $CURRENT_PPP_DEVICE table $CURRENT_TABLE_ID"
    ip -6 route add default via "$CURRENT_NEW_IPV6_ROUTE_VIA_IP" from "$CURRENT_DEFAULT_ROUTE_ADDRESS" dev $CURRENT_PPP_DEVICE table $CURRENT_TABLE_ID
  done
done
